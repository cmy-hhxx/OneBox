import AppKit
import Foundation
import OneBoxDesignSystem
import SwiftUI
import XCTest

@testable import StockWatchTool

@MainActor
final class StockWatchVisualValidationTests: XCTestCase {
    func testLowPriceETFChartAndWorkspaceRendersAtSupportedSizes() async throws {
        let instrument = Instrument(symbol: "159740", name: "恒生科技ETF大成", namespace: .shenzhen)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = instrument.market.timeZone
        let start = try XCTUnwrap(
            calendar.date(
                from: DateComponents(
                    year: 2026, month: 9, day: 11, hour: 9, minute: 30)))
        let bars = (0..<240).map { index in
            let price = 0.534 + Double(index) / 239 * 0.004 + sin(Double(index) / 11) * 0.0006
            let minutes = index + (index >= 120 ? 90 : 0)
            return MinuteBar(
                time: start.addingTimeInterval(Double(minutes) * 60),
                open: price, close: price, high: price, low: price)
        }
        let final = try XCTUnwrap(bars.last)
        let quote = QuoteSnapshot(
            instrumentID: instrument.id, minuteBars: bars, dayOpen: bars[0].close,
            previousClose: 0.536, lastPrice: final.close, marketTime: final.time,
            receivedAt: final.time.addingTimeInterval(1), source: .tencent)
        let chart = PreparedIntradayChart(instrument: instrument, quote: quote)
        for size in [CGSize(width: 716, height: 276), CGSize(width: 356, height: 180)] {
            try await capture(
                StockIntradayDetailView(
                    instrument: instrument, quote: quote, chart: chart, status: .previousSession),
                name: "stock-etf-detail-\(Int(size.width))", width: size.width, height: size.height)
        }
        let database = try MarketDatabase.inMemory()
        try await database.replaceWatchlist(with: [instrument])
        let suite = "OneBox.ChartVisual.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = StockWatchPreferences(defaults: defaults, legacyDefaults: nil)
        let store = MonitorStore(
            client: VisualValidationMarketDataClient(snapshots: [instrument.id: quote]),
            database: database, preferences: preferences,
            refreshNow: { _ in final.time.addingTimeInterval(86_400) })
        try await store.start()
        await store.refreshAll()
        for size in [
            CGSize(width: 716, height: 510), CGSize(width: 356, height: 418),
            CGSize(width: 716, height: 240),
        ] {
            try await capture(
                workspace(store: store, preferences: preferences),
                name: "stock-etf-workspace-\(Int(size.width))-\(Int(size.height))",
                width: size.width, height: size.height)
        }
        let failure = await store.shutdown()
        XCTAssertNil(failure)
    }

    func testResponsiveWorkspaceReferenceRendersProduceInspectablePNGs() async throws {
        let database = try MarketDatabase.inMemory()
        let instruments = Instrument.initialWatchlist
        let snapshots = Dictionary(
            uniqueKeysWithValues: instruments.enumerated().map { index, instrument in
                (
                    instrument.id,
                    Self.snapshot(
                        for: instrument,
                        rising: index != 1
                    )
                )
            }
        )
        for instrument in instruments {
            guard let snapshot = snapshots[instrument.id] else {
                XCTFail("缺少视觉验收行情")
                return
            }
            try await database.saveQuote(snapshot, for: instrument)
        }

        let suiteName = "OneBox.StockWatchVisualValidation.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let preferences = StockWatchPreferences(defaults: defaults, legacyDefaults: nil)
        let store = MonitorStore(
            client: VisualValidationMarketDataClient(snapshots: snapshots),
            database: database,
            preferences: preferences,
            refreshNow: { market in
                guard let instrument = instruments.first(where: { $0.market == market }),
                    let snapshot = snapshots[instrument.id]
                else { return Date() }
                return snapshot.receivedAt
            }
        )
        try await store.start()
        await store.refreshAll()
        let references: [(name: String, width: CGFloat, height: CGFloat)] = [
            ("stock-watch-default-workspace", 716, 510),
            ("stock-watch-minimum-workspace", 616, 418),
            ("stock-watch-compact-workspace", 350, 418),
        ]
        for reference in references {
            let root = workspace(store: store, preferences: preferences)
            try await capture(
                root, name: reference.name, width: reference.width, height: reference.height
            )
        }
        try await capture(
            inspector(store: store, preferences: preferences),
            name: "stock-watch-percentage-inspector", width: 248, height: 900
        )

        var disabledConfiguration = AlertConfiguration.default
        disabledConfiguration.isEnabled = false
        XCTAssertTrue(store.updateAlertConfiguration(disabledConfiguration))
        try await capture(
            inspector(store: store, preferences: preferences),
            name: "stock-watch-alerts-disabled", width: 248, height: 900
        )

        var targetConfiguration = AlertConfiguration.default
        targetConfiguration.basis = .targetPrice
        XCTAssertTrue(store.updateAlertConfiguration(targetConfiguration))
        XCTAssertTrue(
            store.updatePriceTargets(
                for: instruments[0], risingPrice: 106, fallingPrice: 98
            )
        )
        try await capture(
            inspector(store: store, preferences: preferences),
            name: "stock-watch-target-inspector", width: 248, height: 1_100
        )
        try await capture(
            AddInstrumentSheet(store: store, onAdded: { _ in }),
            name: "stock-watch-add-sheet", width: 440, height: 440
        )
        try await capture(
            WatchlistJSONSheet(store: store, copyText: { _ in true }, onImported: {}),
            name: "stock-watch-json-sheet", width: 520, height: 480
        )
        store.testAlert(.rising)
        try await capture(
            workspace(store: store, preferences: preferences),
            name: "stock-watch-alert-workspace", width: 716, height: 510
        )
        let shutdownFailure = await store.shutdown()
        XCTAssertNil(shutdownFailure)

        let previousDatabase = try MarketDatabase.inMemory()
        let previousStore = MonitorStore(
            client: VisualValidationMarketDataClient(snapshots: snapshots),
            database: previousDatabase,
            preferences: preferences,
            refreshNow: { _ in Date(timeIntervalSince1970: 1_789_273_605) }
        )
        try await previousStore.start()
        await previousStore.refreshAll()
        XCTAssertEqual(
            previousStore.quotePresentation.snapshot.monitoredInstruments[instruments[0].id]?
                .status,
            .previousSession
        )
        try await capture(
            workspace(store: previousStore, preferences: preferences),
            name: "stock-watch-previous-session", width: 716, height: 510
        )
        try await capture(
            inspector(store: previousStore, preferences: preferences),
            name: "stock-watch-previous-session-inspector", width: 248, height: 900
        )
        let previousShutdownFailure = await previousStore.shutdown()
        XCTAssertNil(previousShutdownFailure)

        let failureDatabase = try MarketDatabase.inMemory()
        for instrument in instruments {
            try await failureDatabase.saveQuote(
                try XCTUnwrap(snapshots[instrument.id]), for: instrument)
        }
        let failureStore = MonitorStore(
            client: VisualValidationFailingMarketDataClient(),
            database: failureDatabase,
            preferences: preferences
        )
        try await failureStore.start()
        await failureStore.refreshAll()
        XCTAssertNotNil(failureStore.quotePresentation.snapshot.sourceError)
        try await capture(
            workspace(store: failureStore, preferences: preferences),
            name: "stock-watch-source-failure", width: 356, height: 510
        )
        let failedShutdownFailure = await failureStore.shutdown()
        XCTAssertNil(failedShutdownFailure)

        let emptyDatabase = try MarketDatabase.inMemory()
        try await emptyDatabase.replaceWatchlist(with: [])
        let emptyStore = MonitorStore(
            client: VisualValidationMarketDataClient(snapshots: [:]),
            database: emptyDatabase,
            preferences: preferences
        )
        try await emptyStore.start()
        XCTAssertTrue(emptyStore.watchlistPresentation.instruments.isEmpty)
        try await capture(
            workspace(store: emptyStore, preferences: preferences),
            name: "stock-watch-empty-workspace", width: 356, height: 418
        )
        try await capture(
            inspector(store: emptyStore, preferences: preferences),
            name: "stock-watch-empty-inspector", width: 248, height: 900
        )
        let emptyShutdownFailure = await emptyStore.shutdown()
        XCTAssertNil(emptyShutdownFailure)

        let longInstrument = Instrument(
            symbol: "159740",
            name: "恒生科技ETF大成·" + String(repeating: "长名称布局验收", count: 14),
            namespace: .shenzhen
        )
        let longQuote = Self.snapshot(for: longInstrument, rising: true)
        let longDatabase = try MarketDatabase.inMemory()
        try await longDatabase.replaceWatchlist(with: [longInstrument])
        let longStore = MonitorStore(
            client: VisualValidationMarketDataClient(snapshots: [longInstrument.id: longQuote]),
            database: longDatabase,
            preferences: preferences,
            refreshNow: { _ in longQuote.receivedAt }
        )
        try await longStore.start()
        await longStore.refreshAll()
        try await capture(
            workspace(store: longStore, preferences: preferences),
            name: "stock-watch-long-name-workspace", width: 350, height: 418
        )
        try await capture(
            inspector(store: longStore, preferences: preferences),
            name: "stock-watch-long-name-inspector", width: 248, height: 1_100
        )
        let longShutdownFailure = await longStore.shutdown()
        XCTAssertNil(longShutdownFailure)
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func workspace(
        store: MonitorStore, preferences: StockWatchPreferences
    ) -> some View {
        StockWatchWorkspaceView(
            store: store,
            preferences: preferences,
            copyText: { _ in true },
            revealDirectory: { _ in true }
        )
    }

    private func inspector(
        store: MonitorStore, preferences: StockWatchPreferences
    ) -> some View {
        StockWatchInspector(
            store: store,
            preferences: preferences,
            selectedInstrumentID: store.watchlistPresentation.instruments.first?.id,
            copyText: { _ in true },
            revealDirectory: { _ in true }
        )
        .padding(DesignMetrics.space16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(DesignPalette.light.surface)
    }

    private func capture<Content: View>(
        _ content: Content, name: String, width: CGFloat, height: CGFloat
    ) async throws {
        let root =
            content
            .font(DesignTypography.body)
            .tint(DesignPalette.light.accent)
            .foregroundStyle(DesignPalette.light.textPrimary)
            .environment(\.colorScheme, .light)
            .transaction { transaction in transaction.disablesAnimations = true }
            .frame(width: width, height: height)
            .background(DesignPalette.light.background)
        let host = NSHostingView(rootView: root)
        host.appearance = NSAppearance(named: .aqua)
        host.frame = NSRect(x: 0, y: 0, width: width, height: height)
        let window = NSWindow(
            contentRect: host.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.contentView = host
        window.orderFrontRegardless()
        defer {
            window.orderOut(nil)
            window.contentView = nil
        }
        await Task.yield()
        try await Task.sleep(for: .milliseconds(50))
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        XCTAssertGreaterThan(png.count, 10_000)
        XCTAssertEqual(host.bounds.width, width)
        XCTAssertEqual(host.bounds.height, height)
        let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let path = ProcessInfo.processInfo.environment["ONEBOX_UI_SNAPSHOT_DIRECTORY"] {
            let directory = URL(fileURLWithPath: path, isDirectory: true)
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true)
            try png.write(to: directory.appendingPathComponent(name + ".png"))
        }
    }

    private static func snapshot(
        for instrument: Instrument,
        rising: Bool
    ) -> QuoteSnapshot {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = instrument.market.timeZone
        guard
            let start = calendar.date(
                from: DateComponents(
                    timeZone: instrument.market.timeZone,
                    year: 2026,
                    month: 9,
                    day: 11,
                    hour: 9,
                    minute: 30
                )
            )
        else {
            preconditionFailure("无法建立视觉验收时间")
        }
        let direction = rising ? 1.0 : -1.0
        let bars = (0..<60).map { index in
            let price = 100 + direction * Double(index) / 20
            return MinuteBar(
                time: start.addingTimeInterval(Double(index) * 60),
                open: price,
                close: price,
                high: price + 0.1,
                low: price - 0.1
            )
        }
        guard let first = bars.first, let last = bars.last else {
            preconditionFailure("视觉验收行情不能为空")
        }
        return QuoteSnapshot(
            instrumentID: instrument.id,
            minuteBars: bars,
            dayOpen: first.open,
            previousClose: 100,
            lastPrice: last.close,
            marketTime: last.time,
            receivedAt: last.time.addingTimeInterval(1),
            source: .tencent
        )
    }
}

private struct VisualValidationMarketDataClient: MarketDataClient {
    let snapshots: [InstrumentID: QuoteSnapshot]

    func searchInstruments(matching query: String) async throws -> [Instrument] {
        []
    }

    func fetchQuote(for instrument: Instrument) async throws -> QuoteSnapshot {
        guard let snapshot = snapshots[instrument.id] else {
            throw URLError(.resourceUnavailable)
        }
        return snapshot
    }
}

private struct VisualValidationFailingMarketDataClient: MarketDataClient {
    func searchInstruments(matching query: String) async throws -> [Instrument] { [] }
    func fetchQuote(for instrument: Instrument) async throws -> QuoteSnapshot {
        throw NSError(
            domain: NSURLErrorDomain,
            code: NSURLErrorNotConnectedToInternet,
            userInfo: [
                NSLocalizedDescriptionKey:
                    "The Internet connection appears to be offline. 无法连接行情提供方，已保留最近一次有效缓存。"
            ]
        )
    }
}
