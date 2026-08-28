import XCTest

@testable import StockWatchTool

final class TradingCalendarTests: XCTestCase {
    func testSessionDateUsesTheInstrumentMarketTimeZone() throws {
        let instant = try XCTUnwrap(
            ISO8601DateFormatter().date(from: "2026-07-30T16:30:00Z")
        )

        XCTAssertEqual(
            TradingCalendar.sessionDate(for: instant, market: .aShare),
            "2026-07-31"
        )
        XCTAssertEqual(
            TradingCalendar.sessionDate(for: instant, market: .hongKong),
            "2026-07-31"
        )
        XCTAssertEqual(
            TradingCalendar.sessionDate(for: instant, market: .unitedStates),
            "2026-07-30"
        )
    }

    func testAShareReviewMarkersFollowTheQuoteSessionInsteadOfAHolidayTable() throws {
        let formatter = ISO8601DateFormatter()
        let sameSession = quote(
            marketTime: try XCTUnwrap(formatter.date(from: "2026-07-30T06:30:00Z"))
        )
        let beforeClose = try XCTUnwrap(formatter.date(from: "2026-07-30T06:59:00Z"))
        let afterClose = try XCTUnwrap(formatter.date(from: "2026-07-30T07:01:00Z"))
        let nextSession = try XCTUnwrap(formatter.date(from: "2026-07-31T01:31:00Z"))
        let weekend = try XCTUnwrap(formatter.date(from: "2026-08-01T02:00:00Z"))

        XCTAssertFalse(
            TradingCalendar.shouldShowAShareReviewMarkers(for: sameSession, now: beforeClose))
        XCTAssertTrue(
            TradingCalendar.shouldShowAShareReviewMarkers(for: sameSession, now: afterClose))
        XCTAssertTrue(
            TradingCalendar.shouldShowAShareReviewMarkers(for: sameSession, now: nextSession))
        XCTAssertTrue(TradingCalendar.shouldShowAShareReviewMarkers(for: sameSession, now: weekend))

        let futureQuote = quote(
            marketTime: try XCTUnwrap(formatter.date(from: "2026-08-03T02:00:00Z"))
        )
        XCTAssertFalse(
            TradingCalendar.shouldShowAShareReviewMarkers(for: futureQuote, now: weekend))
    }

    private func quote(marketTime: Date) -> QuoteSnapshot {
        QuoteSnapshot(
            instrumentID: Instrument.initialWatchlist[0].id,
            minuteBars: [],
            dayOpen: 1,
            previousClose: 1,
            lastPrice: 1,
            marketTime: marketTime,
            receivedAt: marketTime,
            source: .tencent
        )
    }
}
