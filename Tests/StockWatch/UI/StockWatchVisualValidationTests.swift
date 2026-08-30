import AppKit
import Foundation
import SwiftUI
import XCTest

@testable import StockWatchTool

@MainActor
final class StockWatchVisualValidationTests: XCTestCase {
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
        store.testAlert(.rising)

        let references: [(name: String, width: CGFloat)] = [
            ("stock-watch-wide-workspace", 1_100),
            ("stock-watch-compact-workspace", 640),
        ]
        for reference in references {
            guard
                let png = await renderWorkspace(
                    store: store,
                    preferences: preferences,
                    width: reference.width
                )
            else {
                XCTFail("无法生成 \(reference.name) 视觉验收 PNG")
                _ = await store.shutdown()
                defaults.removePersistentDomain(forName: suiteName)
                return
            }
            XCTAssertGreaterThan(png.count, 10_000)
            let attachment = XCTAttachment(
                data: png,
                uniformTypeIdentifier: "public.png"
            )
            attachment.name = reference.name
            attachment.lifetime = .keepAlways
            add(attachment)
        }

        let shutdownFailure = await store.shutdown()
        XCTAssertNil(shutdownFailure)
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func renderWorkspace(
        store: MonitorStore,
        preferences: StockWatchPreferences,
        width: CGFloat
    ) async -> Data? {
        let root = StockWatchWorkspaceView(
            store: store,
            preferences: preferences,
            copyText: { _ in true },
            revealDirectory: { _ in true }
        )
        .transaction { transaction in
            transaction.disablesAnimations = true
        }
        .frame(width: width, height: 720)
        let host = NSHostingView(rootView: root)
        host.appearance = NSAppearance(named: .aqua)
        host.frame = NSRect(x: 0, y: 0, width: width, height: 720)
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
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()

        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            return nil
        }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        return bitmap.representation(using: .png, properties: [:])
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
                    month: 8,
                    day: 12,
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
