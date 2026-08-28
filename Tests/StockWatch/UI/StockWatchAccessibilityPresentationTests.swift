import Foundation
import XCTest

@testable import StockWatchTool

final class StockWatchAccessibilityPresentationTests: XCTestCase {
    func testIdleRowPresentsFailureBeforeFirstQuote() {
        XCTAssertEqual(
            InstrumentRowPresentation.statusText(
                status: .idle,
                hasQuote: false,
                statusMessage: "行情请求失败"
            ),
            "行情请求失败"
        )
        XCTAssertEqual(
            InstrumentRowPresentation.statusText(
                status: .idle,
                hasQuote: false,
                statusMessage: nil
            ),
            "等待首次刷新"
        )
    }

    func testFlatPercentOmitsPositiveSign() {
        XCTAssertEqual(InstrumentRowPresentation.percentText(0), "0.00%")
        XCTAssertEqual(InstrumentRowPresentation.percentText(1.25), "+1.25%")
    }

    func testRowAccessibilitySummaryIncludesNamespaceDisplayName() {
        let instrument = Instrument.initialWatchlist[0]

        let summary = InstrumentRowPresentation.accessibilitySummary(
            instrument: instrument,
            quote: nil,
            status: .idle,
            statusMessage: nil
        )

        XCTAssertTrue(summary.contains(instrument.symbol))
        XCTAssertTrue(summary.contains(instrument.namespace.displayName))
    }

    func testThresholdAccessibilityValueUsesPercentFormat() {
        XCTAssertEqual(AlertThresholdPresentation.valueText(2.5), "2.5%")
    }

    func testRefreshAccessibilityValueContainsFormattedTime() {
        let refresh = Date(timeIntervalSince1970: 1_700_000_000)

        XCTAssertEqual(
            StockWatchToolbarAccessibility.lastRefreshValue(refresh),
            refresh.formatted(date: .abbreviated, time: .standard)
        )
    }

    func testAddedSearchResultAccessibilityNamesItsIdentityAndState() {
        let instrument = Instrument.initialWatchlist[0]

        let label = AddInstrumentAccessibility.resultActionLabel(
            for: instrument,
            isAdded: true
        )

        XCTAssertTrue(label.contains("已添加"))
        XCTAssertTrue(label.contains(instrument.symbol))
        XCTAssertTrue(label.contains(instrument.namespace.displayName))
    }

    func testJSONReplacementWarningsNameDiscardedTargetsAndQuoteCache() {
        let warnings = [
            WatchlistJSONPresentation.replacementWarning,
            WatchlistJSONPresentation.confirmationMessage(currentCount: 3),
        ]

        for warning in warnings {
            XCTAssertTrue(warning.contains("未保留标的"))
            XCTAssertTrue(warning.contains("目标价格"))
            XCTAssertTrue(warning.contains("行情缓存"))
        }
    }

    func testEmptyJSONListIsEligibleForValidation() {
        XCTAssertTrue(WatchlistJSONPresentation.canImport("[]"))
        XCTAssertFalse(WatchlistJSONPresentation.canImport("  \n"))
    }

    func testOnlyLiveFinitePositivePriceIsPresentedAsCurrent() {
        XCTAssertNil(
            SelectedInstrumentQuotePresentation.livePrice(
                status: .idle,
                lastPrice: 10
            )
        )
        XCTAssertNil(
            SelectedInstrumentQuotePresentation.livePrice(
                status: .stale,
                lastPrice: 10
            )
        )
        XCTAssertNil(
            SelectedInstrumentQuotePresentation.livePrice(
                status: .live,
                lastPrice: .nan
            )
        )
        XCTAssertEqual(
            SelectedInstrumentQuotePresentation.livePrice(
                status: .live,
                lastPrice: 10
            ),
            10
        )
    }
}
