import XCTest

@testable import StockWatchTool

final class IntradayTimelineTests: XCTestCase {
    func testTenMinutesAfterAShareOpenUsesOnlyElapsedSessionWidth() throws {
        let time = try marketTime(hour: 9, minute: 40, market: .aShare)

        let progress = try XCTUnwrap(IntradayTimeline.progress(at: time, market: .aShare))

        XCTAssertEqual(progress, 10.0 / 240.0, accuracy: 0.000_001)
        XCTAssertLessThan(progress, 0.05)
    }

    func testAShareLunchBreakIsFoldedOutOfTheTimeline() throws {
        let morningClose = try marketTime(hour: 11, minute: 30, market: .aShare)
        let afternoonOpen = try marketTime(hour: 13, minute: 0, market: .aShare)
        let duringLunch = try marketTime(hour: 12, minute: 15, market: .aShare)

        XCTAssertEqual(IntradayTimeline.progress(at: morningClose, market: .aShare), 0.5)
        XCTAssertEqual(IntradayTimeline.progress(at: afternoonOpen, market: .aShare), 0.5)
        XCTAssertNil(IntradayTimeline.progress(at: duringLunch, market: .aShare))
    }

    func testOtherMarketsUseTheirFullRegularSessions() throws {
        let hongKongTime = try marketTime(hour: 10, minute: 30, market: .hongKong)
        let unitedStatesTime = try marketTime(hour: 10, minute: 30, market: .unitedStates)

        XCTAssertEqual(
            try XCTUnwrap(IntradayTimeline.progress(at: hongKongTime, market: .hongKong)),
            60.0 / 330.0,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            try XCTUnwrap(IntradayTimeline.progress(at: unitedStatesTime, market: .unitedStates)),
            60.0 / 390.0,
            accuracy: 0.000_001
        )
    }

    private func marketTime(hour: Int, minute: Int, market: Market) throws -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = market.timeZone
        let components = DateComponents(
            timeZone: market.timeZone,
            year: 2026,
            month: 8,
            day: 12,
            hour: hour,
            minute: minute
        )
        return try XCTUnwrap(calendar.date(from: components))
    }
}
