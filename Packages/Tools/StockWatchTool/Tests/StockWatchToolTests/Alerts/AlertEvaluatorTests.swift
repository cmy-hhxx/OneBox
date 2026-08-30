import XCTest

@testable import StockWatchTool

final class AlertEvaluatorTests: XCTestCase {
    func testPercentageRuleRearmsOnlyAfterReturningInsideTheThreshold() {
        var evaluator = AlertEvaluator()
        let rule = AlertRule.percentage(rising: 3, falling: 3)

        XCTAssertEqual(
            evaluator.evaluate(changePercent: 3.1, lastPrice: 103, rule: rule),
            .rising
        )
        XCTAssertNil(evaluator.evaluate(changePercent: 3.8, lastPrice: 104, rule: rule))
        XCTAssertNil(evaluator.evaluate(changePercent: 2.95, lastPrice: 103, rule: rule))
        XCTAssertNil(evaluator.evaluate(changePercent: 2.7, lastPrice: 103, rule: rule))
        XCTAssertEqual(
            evaluator.evaluate(changePercent: 3.2, lastPrice: 104, rule: rule),
            .rising
        )
    }

    func testOppositeThresholdDoesNotForgetEarlierPercentageLatch() {
        var evaluator = AlertEvaluator()
        let rule = AlertRule.percentage(rising: 3, falling: 3)

        XCTAssertEqual(
            evaluator.evaluate(changePercent: 3.1, lastPrice: 103.1, rule: rule),
            .rising
        )
        XCTAssertEqual(
            evaluator.evaluate(changePercent: -3.1, lastPrice: 96.9, rule: rule),
            .falling
        )
        XCTAssertNil(
            evaluator.evaluate(changePercent: 3.1, lastPrice: 103.1, rule: rule)
        )
        XCTAssertNil(
            evaluator.evaluate(changePercent: 0, lastPrice: 100, rule: rule)
        )
        XCTAssertEqual(
            evaluator.evaluate(changePercent: 3.1, lastPrice: 103.1, rule: rule),
            .rising
        )
    }

    func testOppositeThresholdDoesNotForgetEarlierTargetPriceLatch() {
        var evaluator = AlertEvaluator()
        let rule = AlertRule.targetPrice(rising: 103, falling: 97)

        XCTAssertEqual(
            evaluator.evaluate(changePercent: 3.1, lastPrice: 103.1, rule: rule),
            .rising
        )
        XCTAssertEqual(
            evaluator.evaluate(changePercent: -3.1, lastPrice: 96.9, rule: rule),
            .falling
        )
        XCTAssertNil(
            evaluator.evaluate(changePercent: 3.1, lastPrice: 103.1, rule: rule)
        )
        XCTAssertNil(
            evaluator.evaluate(changePercent: 0, lastPrice: 100, rule: rule)
        )
        XCTAssertEqual(
            evaluator.evaluate(changePercent: 3.1, lastPrice: 103.1, rule: rule),
            .rising
        )
    }

    func testTargetPriceRuleUsesRelativeHysteresisBeforeRearming() {
        var evaluator = AlertEvaluator()
        let rule = AlertRule.targetPrice(rising: 103, falling: 97)

        XCTAssertEqual(
            evaluator.evaluate(changePercent: 3, lastPrice: 103, rule: rule),
            .rising
        )
        XCTAssertNil(evaluator.evaluate(changePercent: 2.9, lastPrice: 102.9, rule: rule))
        XCTAssertNil(evaluator.evaluate(changePercent: 2.8, lastPrice: 102.8, rule: rule))
        XCTAssertEqual(
            evaluator.evaluate(changePercent: 3.1, lastPrice: 103.1, rule: rule),
            .rising
        )
        XCTAssertEqual(
            evaluator.evaluate(changePercent: -3.1, lastPrice: 96.9, rule: rule),
            .falling
        )
    }
}
