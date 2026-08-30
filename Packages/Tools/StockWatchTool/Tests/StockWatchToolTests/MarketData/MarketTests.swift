import XCTest

@testable import StockWatchTool

final class MarketTests: XCTestCase {
    func testPriceColorConventionMatchesEachMarket() {
        XCTAssertEqual(Market.aShare.colorRole(isRising: true), .red)
        XCTAssertEqual(Market.hongKong.colorRole(isRising: true), .red)
        XCTAssertEqual(Market.unitedStates.colorRole(isRising: true), .green)
        XCTAssertEqual(Market.aShare.colorRole(isRising: false), .green)
        XCTAssertEqual(Market.unitedStates.colorRole(isRising: false), .red)
    }

    func testZeroChangeUsesNeutralRoleInEveryMarket() {
        XCTAssertEqual(Market.aShare.colorRole(forChange: 0), .neutral)
        XCTAssertEqual(Market.hongKong.colorRole(forChange: 0), .neutral)
        XCTAssertEqual(Market.unitedStates.colorRole(forChange: 0), .neutral)
    }
}
