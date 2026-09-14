import XCTest

@testable import StockWatchTool

final class StockIntradayDetailLayoutTests: XCTestCase {
    func testInspectionChoosesClosestMinuteAndClampsToAvailableData() {
        let points = [point(0), point(0.1), point(0.2)]

        XCTAssertEqual(StockIntradayChartLayout.nearestPointIndex(to: -1, in: points), 0)
        XCTAssertEqual(StockIntradayChartLayout.nearestPointIndex(to: 0.16, in: points), 2)
        XCTAssertEqual(StockIntradayChartLayout.nearestPointIndex(to: 1, in: points), 2)
        XCTAssertNil(StockIntradayChartLayout.nearestPointIndex(to: 0.5, in: []))
    }

    func testInspectionAtFoldedLunchBoundaryUsesAfternoonSample() {
        let points = [point(0), point(0.5), point(0.5), point(1)]

        XCTAssertEqual(StockIntradayChartLayout.nearestPointIndex(to: 0.5, in: points), 2)
    }

    func testEarlySessionKeepsUnelapsedChartSpaceAndPriceExtremaInsidePlot() {
        let layout = StockIntradayChartLayout(
            size: CGSize(width: 324, height: 92),
            low: 0.533,
            high: 0.539
        )
        let earlyPrice = layout.point(progress: 10.0 / 240, price: 0.536)

        XCTAssertEqual(
            (earlyPrice.x - layout.plotRect.minX) / layout.plotRect.width,
            10.0 / 240,
            accuracy: 0.000_001
        )
        XCTAssertEqual(layout.point(progress: 0, price: 0.539).y, layout.plotRect.minY)
        XCTAssertEqual(layout.point(progress: 1, price: 0.533).y, layout.plotRect.maxY)
        XCTAssertEqual(layout.progress(at: -20), 0)
        XCTAssertEqual(layout.progress(at: 400), 1)
    }

    func testSessionTicksShowLocalLunchBoundariesAndMarketClose() {
        let aShare = StockIntradaySessionTick.ticks(for: .aShare, compact: true)
        let hongKong = StockIntradaySessionTick.ticks(for: .hongKong, compact: true)
        let us = StockIntradaySessionTick.ticks(for: .unitedStates, compact: true)

        XCTAssertEqual(aShare[1], StockIntradaySessionTick(progress: 0.5, label: "11:30 / 13:00"))
        XCTAssertEqual(hongKong[1].progress, 150.0 / 330, accuracy: 0.000_001)
        XCTAssertEqual(hongKong[1].label, "12:00 / 13:00")
        XCTAssertEqual(aShare.last?.label, "15:00")
        XCTAssertEqual(hongKong.last?.label, "16:00")
        XCTAssertEqual(us.last?.label, "16:00")
    }

    private func point(_ progress: Double) -> IntradayChartPoint {
        IntradayChartPoint(
            time: Date(timeIntervalSince1970: progress * 1_000 + 1_000),
            progress: progress,
            close: 0.538
        )
    }
}
