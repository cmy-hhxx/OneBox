import XCTest
import os

@testable import StockWatchTool

final class PerformanceBaselineTests: XCTestCase {
    func testTenInstrumentRefreshBaseline() async throws {
        try await measureRefresh(instrumentCount: 10)
    }

    func testHundredInstrumentRefreshBaseline() async throws {
        try await measureRefresh(instrumentCount: 100)
    }

    func testSynchronizingTwoHundredFortyBarsBaseline() async throws {
        let database = try MarketDatabase.inMemory()
        let instrument = Instrument.initialWatchlist[0]
        try await database.replaceWatchlist(with: [instrument])
        let snapshot = Self.snapshot(for: instrument, barCount: 240, dayOffset: 0)

        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()], options: options) {
            waitForAsyncOperation {
                _ = try await database.saveQuote(snapshot, for: instrument)
            }
        }
    }

    func testOpeningBoundedCacheAfterDayTransitionsBaseline() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MarketSpritePerformance.\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent(MarketDatabase.defaultFileName).path
        let instrument = Instrument.initialWatchlist[0]
        let database = try MarketDatabase.open(atPath: path)
        try await database.replaceWatchlist(with: [instrument])
        // Each new trading day replaces the prior cache, so after 252 day
        // transitions the database stays bounded to a single latest session.
        for day in 0..<252 {
            _ = try await database.saveQuote(
                Self.snapshot(for: instrument, barCount: 240, dayOffset: day),
                for: instrument
            )
        }
        try await database.close()

        let reopened = try MarketDatabase.open(atPath: path)
        let barCount = try await reopened.quoteBarCount()
        XCTAssertEqual(barCount, 240)
        try await reopened.close()

        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()], options: options) {
            waitForAsyncOperation {
                let reopened = try MarketDatabase.open(atPath: path)
                _ = try await reopened.loadLatestQuotes(for: [instrument])
                try await reopened.close()
            }
        }
    }

    func testOpeningHundredInstrumentCacheBaseline() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MarketSpritePerformance.\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let instruments = (0..<100).map { index in
            Instrument(symbol: "C\(index)", name: "缓存基线 \(index)", namespace: .unitedStates)
        }
        let path = directory.appendingPathComponent(MarketDatabase.defaultFileName).path
        let database = try MarketDatabase.open(atPath: path)
        try await database.replaceWatchlist(with: instruments)
        for instrument in instruments {
            try await database.saveQuote(
                Self.snapshot(for: instrument, barCount: 240, dayOffset: 0),
                for: instrument
            )
        }
        try await database.close()

        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()], options: options) {
            waitForAsyncOperation {
                let reopened = try MarketDatabase.open(atPath: path)
                let snapshots = try await reopened.loadLatestQuotes(for: instruments)
                XCTAssertEqual(snapshots.count, instruments.count)
                try await reopened.close()
            }
        }
    }

    private func measureRefresh(instrumentCount: Int) async throws {
        let database = try MarketDatabase.inMemory()
        let instruments = (0..<instrumentCount).map { index in
            Instrument(
                symbol: "P\(index)",
                name: "性能基线 \(index)",
                namespace: .unitedStates
            )
        }
        try await database.replaceWatchlist(with: instruments)
        let coordinator = QuoteRefreshCoordinator(
            client: BenchmarkMarketDataClient(),
            database: database,
            maximumConcurrentRequests: 6
        )

        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()], options: options) {
            waitForAsyncOperation {
                _ = await coordinator.refresh(instruments: instruments, currentQuotes: [:])
            }
        }
    }

    private var options: XCTMeasureOptions {
        let options = XCTMeasureOptions()
        options.iterationCount = 3
        return options
    }

    private func waitForAsyncOperation(
        _ operation: @escaping @Sendable () async throws -> Void
    ) {
        let semaphore = DispatchSemaphore(value: 0)
        let succeeded = OSAllocatedUnfairLock(initialState: true)
        Task {
            do {
                try await operation()
            } catch {
                succeeded.withLock { $0 = false }
            }
            semaphore.signal()
        }
        XCTAssertEqual(semaphore.wait(timeout: .now() + 30), .success)
        XCTAssertTrue(succeeded.withLock { $0 })
    }

    private static func snapshot(
        for instrument: Instrument,
        barCount: Int,
        dayOffset: Int
    ) -> QuoteSnapshot {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
            .addingTimeInterval(Double(dayOffset) * 86_400)
        let bars = (0..<barCount).map { index in
            let price = 100 + Double(index) / 100
            return MinuteBar(
                time: base.addingTimeInterval(Double(index) * 60),
                open: price,
                close: price + 0.01,
                high: price + 0.02,
                low: price - 0.01
            )
        }
        return QuoteSnapshot(
            instrumentID: instrument.id,
            minuteBars: bars,
            dayOpen: 100,
            previousClose: 99,
            lastPrice: bars.last?.close ?? 100,
            marketTime: bars.last?.time ?? base,
            receivedAt: (bars.last?.time ?? base).addingTimeInterval(1),
            source: .tencent
        )
    }
}

final class ChartPerformanceBaselineTests: XCTestCase {
    func testTwoThousandPointChartPreparationBaseline() {
        let bars = Self.chartBars(count: 2_000)

        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()], options: options) {
            let preparation = IntradayChartPreparation(
                points: bars,
                market: .aShare,
                dayOpen: 100,
                previousClose: 100,
                showReviewMarkers: true
            )
            XCTAssertEqual(preparation.points.count, bars.count)
        }
    }

    func testEightVisibleRowsChartPreparationBaseline() {
        let rows = (0..<8).map { index in
            Self.chartBars(count: 240, offset: Double(index))
        }

        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()], options: options) {
            for bars in rows {
                let preparation = IntradayChartPreparation(
                    points: bars,
                    market: .aShare,
                    dayOpen: 100,
                    previousClose: 100,
                    showReviewMarkers: true
                )
                XCTAssertEqual(preparation.points.count, bars.count)
            }
        }
    }

    private var options: XCTMeasureOptions {
        let options = XCTMeasureOptions()
        options.iterationCount = 3
        return options
    }

    private static func chartBars(count: Int, offset: Double = 0) -> [MinuteBar] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Market.aShare.timeZone
        guard
            let start = calendar.date(
                from: DateComponents(
                    timeZone: Market.aShare.timeZone,
                    year: 2026,
                    month: 8,
                    day: 12,
                    hour: 9,
                    minute: 30
                ))
        else {
            preconditionFailure("无法建立图表性能基线时间")
        }
        return (0..<count).map { index in
            let price = 100 + offset + sin(Double(index) / 20)
            let sessionMinute = index % 240
            let elapsedMinute = sessionMinute < 120 ? sessionMinute : sessionMinute + 90
            return MinuteBar(
                time: start.addingTimeInterval(Double(elapsedMinute) * 60),
                open: price,
                close: price,
                high: price + 0.1,
                low: price - 0.1
            )
        }
    }
}

private struct BenchmarkMarketDataClient: MarketDataClient {
    func searchInstruments(matching query: String) async throws -> [Instrument] {
        []
    }

    func fetchQuote(for instrument: Instrument) async throws -> QuoteSnapshot {
        let time = Date(timeIntervalSince1970: 1_700_000_000)
        return QuoteSnapshot(
            instrumentID: instrument.id,
            minuteBars: [
                MinuteBar(time: time, open: 99, close: 100, high: 101, low: 98)
            ],
            dayOpen: 99,
            previousClose: 98,
            lastPrice: 100,
            marketTime: time,
            receivedAt: time.addingTimeInterval(1),
            source: .tencent
        )
    }
}
