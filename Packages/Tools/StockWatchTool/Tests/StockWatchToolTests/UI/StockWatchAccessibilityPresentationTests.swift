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

    func testCompactRowKeepsEveryCoreMarketFieldWithoutTheChart() {
        let compactFields = StockWatchRowLayout.compact.visibleFields

        XCTAssertTrue(compactFields.contains(.identity))
        XCTAssertTrue(compactFields.contains(.code))
        XCTAssertTrue(compactFields.contains(.status))
        XCTAssertTrue(compactFields.contains(.price))
        XCTAssertTrue(compactFields.contains(.changeDirection))
        XCTAssertFalse(compactFields.contains(.intradayChart))
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

    @MainActor
    func testThresholdDraftCommitsOnlyOnceWhenEditingEnds() {
        let initial = AlertConfiguration.default
        let presentation = AlertThresholdPresentationSession(configuration: initial)
        var committedConfigurations: [AlertConfiguration] = []

        presentation.editingChanged(
            true,
            field: .rising,
            currentConfiguration: initial,
            commit: { committedConfigurations.append($0) }
        )
        presentation.risingThreshold = 4
        presentation.risingThreshold = 5
        presentation.risingThreshold = 6

        XCTAssertTrue(committedConfigurations.isEmpty)

        presentation.editingChanged(
            false,
            field: .rising,
            currentConfiguration: initial,
            commit: { committedConfigurations.append($0) }
        )

        XCTAssertEqual(committedConfigurations.count, 1)
        XCTAssertEqual(committedConfigurations.first?.risingThreshold, 6)
        XCTAssertEqual(committedConfigurations.first?.fallingThreshold, initial.fallingThreshold)
    }

    @MainActor
    func testThresholdDraftPreservesConcurrentNonThresholdConfigurationChanges() {
        let initial = AlertConfiguration.default
        let presentation = AlertThresholdPresentationSession(configuration: initial)
        presentation.editingChanged(
            true,
            field: .falling,
            currentConfiguration: initial,
            commit: { _ in XCTFail("Editing start must not commit") }
        )
        presentation.fallingThreshold = 7

        var current = initial
        current.basis = .targetPrice
        var committed: AlertConfiguration?
        presentation.editingChanged(
            false,
            field: .falling,
            currentConfiguration: current,
            commit: { committed = $0 }
        )

        XCTAssertEqual(committed?.basis, .targetPrice)
        XCTAssertEqual(committed?.risingThreshold, initial.risingThreshold)
        XCTAssertEqual(committed?.fallingThreshold, 7)
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
