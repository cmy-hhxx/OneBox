import XCTest

@testable import StockWatchTool

final class IntradayChartPreparationTests: XCTestCase {
    func testLowPriceETFMovementUsesMostOfThePriceDomain() {
        let chart = preparation(closes: [0.536, 0.534, 0.538], previousClose: 0.536)

        let visibleMovement = (0.538 - 0.534) / (chart.high - chart.low)

        XCTAssertGreaterThan(visibleMovement, 0.7)
        XCTAssertLessThan(chart.low, 0.534)
        XCTAssertGreaterThan(chart.high, 0.538)
    }

    func testFlatPricesHaveFiniteNonzeroDomainsAtDifferentPriceScales() {
        for price in [0.001, 0.538, 10, 100_000] {
            let chart = preparation(closes: [price, price], previousClose: price)

            XCTAssertTrue(chart.low.isFinite)
            XCTAssertTrue(chart.high.isFinite)
            XCTAssertLessThan(chart.low, price)
            XCTAssertGreaterThan(chart.high, price)
            XCTAssertLessThan((chart.high - chart.low) / price, 0.002)
        }
    }

    func testDomainIncludesDayOpenAndPreviousCloseOutsideMinutePrices() {
        let chart = IntradayChartPreparation(
            points: [
                bar(hour: 9, minute: 30, close: 0.534),
                bar(hour: 10, minute: 0, close: 0.536),
            ],
            market: .aShare,
            dayOpen: 0.540,
            previousClose: 0.530,
            showReviewMarkers: false
        )

        XCTAssertLessThan(chart.low, 0.530)
        XCTAssertGreaterThan(chart.high, 0.540)
    }

    func testPreparedPointsRetainExactTimesAcrossFoldedLunchBoundary() {
        let bars = [
            bar(hour: 11, minute: 30, close: 0.534),
            bar(hour: 13, minute: 0, close: 0.536),
        ]
        let chart = IntradayChartPreparation(
            points: bars,
            market: .aShare,
            dayOpen: 0.534,
            previousClose: 0.536,
            showReviewMarkers: false
        )

        XCTAssertEqual(chart.points.map(\.time), bars.map(\.time))
        XCTAssertEqual(chart.points.map(\.progress), [0.5, 0.5])
    }

    func testFiltersLunchBreakAndSelectsProfitPairForADownCloseWithRebound() throws {
        let preparation = IntradayChartPreparation(
            points: [
                bar(hour: 9, minute: 30, close: 10),
                bar(hour: 10, minute: 0, close: 7),
                bar(hour: 10, minute: 30, close: 8),
                bar(hour: 12, minute: 0, close: 6),
            ],
            market: .aShare,
            dayOpen: 9,
            previousClose: 9,
            showReviewMarkers: true
        )

        XCTAssertEqual(preparation.points.map(\.close), [10, 7, 8])
        XCTAssertEqual(preparation.points[1].progress, 0.125, accuracy: 0.000_001)
        XCTAssertEqual(
            preparation.reviewMarkers,
            IntradayReviewMarkerSelection(buyIndex: 1, sellIndex: 2)
        )
        XCTAssertLessThan(preparation.low, 7)
        XCTAssertGreaterThan(preparation.high, 10)
    }

    func testUpCloseSelectsTheLargestTimeOrderedProfitPair() throws {
        let preparation = preparation(
            closes: [12, 8, 11, 10],
            previousClose: 9
        )

        XCTAssertEqual(
            preparation.reviewMarkers,
            IntradayReviewMarkerSelection(buyIndex: 1, sellIndex: 2)
        )
    }

    func testMonotonicDeclineHasOnlySellMarker() throws {
        let preparation = preparation(
            closes: [12, 11, 10],
            previousClose: 9
        )

        XCTAssertEqual(
            preparation.reviewMarkers,
            IntradayReviewMarkerSelection(buyIndex: nil, sellIndex: 0)
        )
    }

    func testFlatCloseStillSelectsTheLargestIntradayProfitPair() throws {
        let preparation = preparation(
            closes: [10, 7, 12, 10],
            previousClose: 10
        )

        XCTAssertEqual(
            preparation.reviewMarkers,
            IntradayReviewMarkerSelection(buyIndex: 1, sellIndex: 2)
        )
    }

    func testFlatIntradayPricesHaveNoMarkers() throws {
        let preparation = preparation(
            closes: [10, 10, 10],
            previousClose: 9
        )

        XCTAssertNil(preparation.reviewMarkers)
    }

    func testRepeatedBestPairsUseTheFirstOccurrence() throws {
        let preparation = preparation(
            closes: [9, 7, 10, 7, 10],
            previousClose: 6
        )

        XCTAssertEqual(
            preparation.reviewMarkers,
            IntradayReviewMarkerSelection(buyIndex: 1, sellIndex: 2)
        )
    }

    func testFewerThanTwoPointsHasNoMarkers() throws {
        XCTAssertNil(preparation(closes: [], previousClose: 10).reviewMarkers)
        XCTAssertNil(preparation(closes: [10], previousClose: 9).reviewMarkers)
    }

    func testSkipsReviewMarkerWorkWhenMarkersAreHidden() throws {
        let preparation = IntradayChartPreparation(
            points: [
                bar(hour: 9, minute: 30, close: 10),
                bar(hour: 10, minute: 0, close: 7),
                bar(hour: 10, minute: 30, close: 8),
            ],
            market: .aShare,
            dayOpen: 9,
            previousClose: 8,
            showReviewMarkers: false
        )

        XCTAssertNil(preparation.reviewMarkers)
    }

    private func preparation(
        closes: [Double],
        previousClose: Double
    ) -> IntradayChartPreparation {
        IntradayChartPreparation(
            points: closes.enumerated().map { index, close in
                bar(hour: 9, minute: 30 + index, close: close)
            },
            market: .aShare,
            dayOpen: closes.first ?? previousClose,
            previousClose: previousClose,
            showReviewMarkers: true
        )
    }

    private func bar(hour: Int, minute: Int, close: Double) -> MinuteBar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Market.aShare.timeZone
        let time = calendar.date(
            from: DateComponents(
                timeZone: Market.aShare.timeZone,
                year: 2026,
                month: 8,
                day: 12,
                hour: hour,
                minute: minute
            ))!
        return MinuteBar(time: time, open: close, close: close, high: close, low: close)
    }
}
