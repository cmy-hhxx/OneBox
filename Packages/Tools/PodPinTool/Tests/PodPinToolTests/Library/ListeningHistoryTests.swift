import XCTest

@testable import PodPinTool

final class ListeningHistoryTests: XCTestCase {
    func testRecordsOnlyPlayedIntervalsAndPreservesSkippedGaps() {
        var history = ListeningHistory()

        history.record(from: 0, to: 10, duration: 100)
        history.record(from: 9.5, to: 20, duration: 100)
        history.record(from: 60, to: 70, duration: 100)

        XCTAssertEqual(
            history.intervals,
            [
                ListenedInterval(start: 0, end: 20),
                ListenedInterval(start: 60, end: 70),
            ])
        XCTAssertEqual(history.listenedFraction(duration: 100), 0.3, accuracy: 0.001)
        XCTAssertFalse(history.isComplete(duration: 100))
    }

    func testBecomesCompleteOnlyAfterRemainingGapsArePlayed() {
        var history = ListeningHistory(intervals: [
            ListenedInterval(start: 0, end: 20),
            ListenedInterval(start: 40, end: 100),
        ])

        XCTAssertFalse(history.isComplete(duration: 100))

        history.record(from: 20, to: 40, duration: 100)

        XCTAssertEqual(history.intervals, [ListenedInterval(start: 0, end: 100)])
        XCTAssertTrue(history.isComplete(duration: 100))
    }

    func testSmallSkippedGapStillPreventsCompletion() {
        let history = ListeningHistory(intervals: [
            ListenedInterval(start: 0, end: 49.9),
            ListenedInterval(start: 50.1, end: 100),
        ])

        XCTAssertFalse(history.isComplete(duration: 100))
        XCTAssertEqual(history.intervals.count, 2)
    }
}
