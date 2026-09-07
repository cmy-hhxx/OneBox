import AppKit
import Foundation
import SwiftUI
import XCTest

@testable import StockWatchTool

@MainActor
final class WorkspacePerformanceTests: XCTestCase {
    func testTenInstrumentWorkspaceFirstRenderBaseline() async throws {
        try await measureFirstRender(instrumentCount: 10)
    }

    func testHundredInstrumentWorkspaceFirstRenderBaseline() async throws {
        try await measureFirstRender(instrumentCount: 100)
    }

    func testTenInstrumentWorkspaceQuoteBatchUpdateBaseline() async throws {
        try await measureQuoteBatchUpdates(instrumentCount: 10)
    }

    func testHundredInstrumentWorkspaceQuoteBatchUpdateBaseline() async throws {
        try await measureQuoteBatchUpdates(instrumentCount: 100)
    }

    private let metrics: [XCTMetric] = [
        XCTClockMetric(),
        XCTMemoryMetric(),
    ]

    private var options: XCTMeasureOptions {
        let options = XCTMeasureOptions()
        options.iterationCount = 30
        return options
    }

    private func measureFirstRender(instrumentCount: Int) async throws {
        let fixture = try await makeFixture(instrumentCount: instrumentCount)
        autoreleasepool {
            let warmupHost = makeHost(fixture: fixture)
            warmupHost.layoutSubtreeIfNeeded()
        }
        var durations: [TimeInterval] = []

        measure(metrics: metrics, options: options) {
            StockWatchPerformanceBudget.recordInteraction(in: &durations) {
                autoreleasepool {
                    let host = makeHost(fixture: fixture)
                    host.layoutSubtreeIfNeeded()
                    XCTAssertGreaterThan(host.fittingSize.height, 0)
                }
            }
        }
        StockWatchPerformanceBudget.assertInteractionP95(durations)

        let shutdownFailure = await fixture.store.shutdown()
        XCTAssertNil(shutdownFailure)
        fixture.removeDefaults()
    }

    private func measureQuoteBatchUpdates(instrumentCount: Int) async throws {
        let fixture = try await makeFixture(instrumentCount: instrumentCount)
        let host = makeHost(fixture: fixture)
        host.layoutSubtreeIfNeeded()
        let batch = QuoteRefreshBatch(
            outcomes: fixture.store.instruments.enumerated().map { index, instrument in
                QuoteRefreshOutcome(
                    instrument: instrument,
                    result: .updated(
                        Self.snapshot(for: instrument, offset: Double(index) + 0.25),
                        storageError: nil
                    )
                )
            }
        )
        fixture.store.applyRefreshBatchForTesting(batch)
        host.layoutSubtreeIfNeeded()
        var durations: [TimeInterval] = []

        measure(metrics: metrics, options: options) {
            StockWatchPerformanceBudget.recordInteraction(in: &durations) {
                fixture.store.applyRefreshBatchForTesting(batch)
                host.layoutSubtreeIfNeeded()
                XCTAssertEqual(
                    fixture.store.instruments.count(where: {
                        fixture.store.monitoredInstrument(for: $0.id)?.status == .live
                    }),
                    instrumentCount
                )
            }
        }
        StockWatchPerformanceBudget.assertInteractionP95(durations)

        let shutdownFailure = await fixture.store.shutdown()
        XCTAssertNil(shutdownFailure)
        fixture.removeDefaults()
    }

    private func makeFixture(instrumentCount: Int) async throws -> WorkspaceFixture {
        let database = try MarketDatabase.inMemory()
        let instruments = (0..<instrumentCount).map { index in
            Instrument(
                symbol: "W\(index)",
                name: "工作区基线 \(index)",
                namespace: .unitedStates
            )
        }
        try await database.replaceWatchlist(with: instruments)
        let snapshots = Dictionary(
            uniqueKeysWithValues: instruments.enumerated().map { index, instrument in
                (instrument.id, Self.snapshot(for: instrument, offset: Double(index)))
            }
        )
        for instrument in instruments {
            let snapshot = try XCTUnwrap(snapshots[instrument.id])
            try await database.saveQuote(snapshot, for: instrument)
        }

        let suiteName = "OneBox.StockWatchWorkspacePerformance.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let preferences = StockWatchPreferences(defaults: defaults, legacyDefaults: nil)
        preferences.refreshInterval = 60
        let store = MonitorStore(
            client: WorkspaceBenchmarkMarketDataClient(snapshots: snapshots),
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

        return WorkspaceFixture(
            store: store,
            preferences: preferences,
            defaults: defaults,
            suiteName: suiteName
        )
    }

    private func makeHost(
        fixture: WorkspaceFixture
    ) -> NSHostingView<WorkspaceBenchmarkRoot> {
        let host = NSHostingView(
            rootView: WorkspaceBenchmarkRoot(
                store: fixture.store,
                preferences: fixture.preferences
            )
        )
        host.frame = NSRect(x: 0, y: 0, width: 1_100, height: 720)
        return host
    }

    private static func snapshot(
        for instrument: Instrument,
        offset: Double
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
                ))
        else {
            preconditionFailure("无法建立工作区性能基线时间")
        }
        let bars = (0..<240).map { index in
            let price = 100 + offset + sin(Double(index) / 20)
            return MinuteBar(
                time: start.addingTimeInterval(Double(index) * 60),
                open: price,
                close: price,
                high: price + 0.1,
                low: price - 0.1
            )
        }
        return QuoteSnapshot(
            instrumentID: instrument.id,
            minuteBars: bars,
            dayOpen: 100 + offset,
            previousClose: 99 + offset,
            lastPrice: bars.last?.close ?? 100,
            marketTime: bars.last?.time ?? start,
            receivedAt: (bars.last?.time ?? start).addingTimeInterval(1),
            source: .tencent
        )
    }
}

@MainActor
private struct WorkspaceBenchmarkRoot: View {
    let store: MonitorStore
    let preferences: StockWatchPreferences

    var body: some View {
        StockWatchWorkspaceView(
            store: store,
            preferences: preferences,
            copyText: { _ in true },
            revealDirectory: { _ in true }
        )
        .transaction { transaction in
            transaction.disablesAnimations = true
        }
        .frame(width: 1_100, height: 720)
    }
}

@MainActor
private struct WorkspaceFixture {
    let store: MonitorStore
    let preferences: StockWatchPreferences
    let defaults: UserDefaults
    let suiteName: String

    func removeDefaults() {
        defaults.removePersistentDomain(forName: suiteName)
    }
}

private struct WorkspaceBenchmarkMarketDataClient: MarketDataClient {
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
