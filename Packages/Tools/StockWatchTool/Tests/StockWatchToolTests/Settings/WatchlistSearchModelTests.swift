import Combine
import XCTest

@testable import StockWatchTool

@MainActor
final class WatchlistSearchModelTests: XCTestCase {
    func testLatestRequestWinsWhenEarlierRequestCompletesLate() async {
        let harness = SearchHarness()
        let model = WatchlistSearchModel { query in
            try await harness.search(query)
        }

        model.query = "旧查询"
        model.submit()
        await harness.waitUntilStarted(count: 1)

        model.query = "新查询"
        model.submit()
        await harness.waitUntilStarted(count: 2)

        let expected = Self.instrument(symbol: "NEW")
        await harness.resolve(query: "新查询", with: [expected])
        await waitUntil { model.results == [expected] }

        await harness.resolve(query: "旧查询", with: [Self.instrument(symbol: "OLD")])
        await Task.yield()

        XCTAssertEqual(model.results, [expected])
        XCTAssertNil(model.message)
        XCTAssertFalse(model.isSearching)
    }

    func testEditingQueryCancelsInFlightSearchWithoutShowingFailure() async {
        let harness = SearchHarness()
        let model = WatchlistSearchModel { query in
            try await harness.search(query)
        }

        model.query = "旧查询"
        model.submit()
        await harness.waitUntilStarted(count: 1)

        model.query = "新查询"
        await harness.waitUntilCancelled(query: "旧查询")

        XCTAssertTrue(model.results.isEmpty)
        XCTAssertNil(model.message)
        XCTAssertFalse(model.isSearching)
    }

    func testFailedSearchCanRetryTheSameQuery() async {
        let harness = SearchHarness()
        let model = WatchlistSearchModel { query in
            try await harness.search(query)
        }

        model.query = "AAPL"
        model.submit()
        await harness.waitUntilStarted(count: 1)
        await harness.fail(query: "AAPL", with: URLError(.notConnectedToInternet))
        await waitUntil { model.message != nil }
        XCTAssertTrue(model.isPresentingSearch)
        XCTAssertTrue(model.hasSearchFailure)

        model.submit()
        await harness.waitUntilStarted(count: 2)
        let expected = Self.instrument(symbol: "AAPL")
        await harness.resolve(query: "AAPL", with: [expected])
        await waitUntil { model.results == [expected] }

        XCTAssertNil(model.message)
        XCTAssertFalse(model.isSearching)
        XCTAssertFalse(model.hasSearchFailure)
    }

    func testSearchResultsAreDeduplicatedByInstrumentIdentity() async {
        let expected = Self.instrument(symbol: "AAPL")
        let model = WatchlistSearchModel { _ in [expected, expected] }

        model.query = "AAPL"
        model.submit()
        await waitUntil { !model.isSearching }

        XCTAssertEqual(model.results, [expected])
    }

    func testCancelStopsTheInFlightRequest() async {
        let harness = SearchHarness()
        let model = WatchlistSearchModel { query in
            try await harness.search(query)
        }

        model.query = "AAPL"
        model.submit()
        await harness.waitUntilStarted(count: 1)
        model.cancel()
        await harness.waitUntilCancelled(query: "AAPL")

        XCTAssertFalse(model.isSearching)
        XCTAssertTrue(model.results.isEmpty)
        XCTAssertNil(model.message)
        XCTAssertFalse(model.hasSearchFailure)
    }

    func testCancelReturnsToWatchlistAfterCompletedSearch() async {
        let expected = Self.instrument(symbol: "AAPL")
        let model = WatchlistSearchModel { _ in [expected] }

        model.query = "AAPL"
        model.submit()
        await waitUntil { model.results == [expected] }
        XCTAssertTrue(model.isPresentingSearch)

        model.cancel()

        XCTAssertEqual(model.query, "")
        XCTAssertTrue(model.results.isEmpty)
        XCTAssertNil(model.message)
        XCTAssertFalse(model.isSearching)
        XCTAssertFalse(model.isPresentingSearch)
    }

    func testEmptySearchPresentsNoResultsState() async {
        let model = WatchlistSearchModel { _ in [] }

        model.query = "不存在的标的"
        model.submit()
        await waitUntil { model.message != nil }

        XCTAssertTrue(model.results.isEmpty)
        XCTAssertTrue(model.isPresentingSearch)
        XCTAssertFalse(model.hasSearchFailure)
    }

    func testEditingIdleQueryPublishesSingleViewInvalidation() {
        let model = WatchlistSearchModel { _ in [] }
        var invalidationCount = 0
        let subscription = model.objectWillChange.sink {
            invalidationCount += 1
        }

        model.query = "A"

        XCTAssertEqual(invalidationCount, 1)
        withExtendedLifetime(subscription) {}
    }

    func testSubmittingIdleQueryPublishesOnlySearchingState() {
        let model = WatchlistSearchModel { _ in
            try await Task.sleep(for: .seconds(60))
            return []
        }
        model.query = "A"
        var invalidationCount = 0
        let subscription = model.objectWillChange.sink {
            invalidationCount += 1
        }

        model.submit()

        XCTAssertEqual(invalidationCount, 1)
        model.cancel()
        withExtendedLifetime(subscription) {}
    }

    private func waitUntil(
        _ condition: @escaping @MainActor () -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(2))
        while !condition(), clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(1))
        }
        guard condition() else {
            XCTFail("Timed out after 2 seconds waiting for condition", file: file, line: line)
            return
        }
    }

    private static func instrument(symbol: String) -> Instrument {
        Instrument(symbol: symbol, name: "测试 \(symbol)", namespace: .unitedStates)
    }
}

private actor SearchHarness {
    private var startedQueries: [String] = []
    private var cancelledQueries = Set<String>()
    private var continuations: [String: CheckedContinuation<[Instrument], Error>] = [:]

    func search(_ query: String) async throws -> [Instrument] {
        startedQueries.append(query)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                continuations[query] = continuation
            }
        } onCancel: {
            Task { await self.recordCancellation(of: query) }
        }
    }

    func resolve(query: String, with instruments: [Instrument]) {
        let continuation = continuations.removeValue(forKey: query)
        continuation?.resume(returning: instruments)
    }

    func fail(query: String, with error: Error) {
        let continuation = continuations.removeValue(forKey: query)
        continuation?.resume(throwing: error)
    }

    func waitUntilStarted(
        count: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(2))
        while startedQueries.count < count, clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(1))
        }
        guard startedQueries.count >= count else {
            XCTFail(
                "Timed out after 2 seconds waiting for \(count) searches to start; "
                    + "started \(startedQueries.count): \(startedQueries)",
                file: file,
                line: line
            )
            return
        }
    }

    func waitUntilCancelled(
        query: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(2))
        while !cancelledQueries.contains(query), clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(1))
        }
        guard cancelledQueries.contains(query) else {
            XCTFail(
                "Timed out after 2 seconds waiting for cancellation of \(query)",
                file: file,
                line: line
            )
            return
        }
    }

    private func recordCancellation(of query: String) {
        cancelledQueries.insert(query)
    }
}
