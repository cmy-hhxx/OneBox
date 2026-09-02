import XCTest

@testable import StockWatchTool

final class QuoteSnapshotTests: XCTestCase {
    func testChangePercentIsDerivedFromThePreviousClose() {
        let snapshot = QuoteSnapshot(
            instrumentID: InstrumentID(rawValue: "us:AAPL"),
            minuteBars: [],
            dayOpen: 100,
            previousClose: 100,
            lastPrice: 103.5,
            marketTime: Date(timeIntervalSince1970: 1_700_000_000),
            receivedAt: Date(timeIntervalSince1970: 1_700_000_001),
            source: .tencent
        )

        XCTAssertEqual(snapshot.changePercent, 3.5, accuracy: 0.0001)
    }
    func testValidationRejectsSnapshotWithoutMinuteBars() throws {
        let instrument = Instrument.initialWatchlist[2]
        let snapshot = QuoteSnapshot(
            instrumentID: instrument.id,
            minuteBars: [],
            dayOpen: 100,
            previousClose: 100,
            lastPrice: 103.5,
            marketTime: Date(timeIntervalSince1970: 1_700_000_000),
            receivedAt: Date(timeIntervalSince1970: 1_700_000_001),
            source: .tencent
        )

        XCTAssertThrowsError(
            try QuoteSnapshotValidator.validatedSessionDate(
                for: snapshot,
                instrument: instrument
            )
        ) { error in
            XCTAssertEqual(error as? QuoteSnapshotValidationError, .missingMinuteBars)
        }
    }

}
