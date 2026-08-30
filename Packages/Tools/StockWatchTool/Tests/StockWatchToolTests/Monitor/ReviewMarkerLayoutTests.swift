import XCTest

@testable import StockWatchTool

final class ReviewMarkerLayoutTests: XCTestCase {
    func testUsesSmallerMarkerInsetsOnlyWhenMarkersAreVisible() {
        XCTAssertEqual(
            ReviewMarkerLayout.plotInsets(hasMarkers: false, isCompact: false),
            .zero
        )
        XCTAssertEqual(
            ReviewMarkerLayout.plotInsets(hasMarkers: true, isCompact: false),
            ReviewMarkerInsets(horizontal: 6, vertical: 7)
        )
        XCTAssertEqual(
            ReviewMarkerLayout.plotInsets(hasMarkers: true, isCompact: true),
            ReviewMarkerInsets(horizontal: 5, vertical: 6)
        )
    }

    func testStandardMarkerClampsAnchorAndLabelAtTopLeft() {
        let layout = ReviewMarkerLayout(
            canvasSize: CGSize(width: 120, height: 58),
            anchor: CGPoint(x: -20, y: -10),
            labelAbove: true,
            isCompact: false
        )

        XCTAssertEqual(layout.fontSize, 12)
        XCTAssertEqual(layout.pointDiameter, 3)
        XCTAssertEqual(layout.markerPoint, CGPoint(x: 6, y: 7))
        XCTAssertGreaterThanOrEqual(layout.labelPoint.y, 6)
        XCTAssertLessThanOrEqual(layout.labelPoint.y, 52)
    }

    func testCompactMarkerClampsAnchorAndLabelAtBottomRight() {
        let layout = ReviewMarkerLayout(
            canvasSize: CGSize(width: 100, height: 45),
            anchor: CGPoint(x: 120, y: 80),
            labelAbove: false,
            isCompact: true
        )

        XCTAssertEqual(layout.fontSize, 12)
        XCTAssertEqual(layout.pointDiameter, 3)
        XCTAssertEqual(layout.markerPoint, CGPoint(x: 95, y: 39))
        XCTAssertGreaterThanOrEqual(layout.labelPoint.y, 5.5)
        XCTAssertLessThanOrEqual(layout.labelPoint.y, 39.5)
    }

    func testMarkersStayInsideAllCanvasEdges() {
        let canvasSize = CGSize(width: 120, height: 58)
        let anchors: [(point: CGPoint, labelAbove: Bool)] = [
            (CGPoint(x: 60, y: -20), true),
            (CGPoint(x: 60, y: 80), false),
            (CGPoint(x: -20, y: 29), true),
            (CGPoint(x: 140, y: 29), false),
        ]

        for item in anchors {
            let layout = ReviewMarkerLayout(
                canvasSize: canvasSize,
                anchor: item.point,
                labelAbove: item.labelAbove,
                isCompact: false
            )

            XCTAssertGreaterThanOrEqual(layout.markerPoint.x, 6)
            XCTAssertLessThanOrEqual(layout.markerPoint.x, 114)
            XCTAssertGreaterThanOrEqual(layout.markerPoint.y, 7)
            XCTAssertLessThanOrEqual(layout.markerPoint.y, 51)
            XCTAssertGreaterThanOrEqual(layout.labelPoint.x, 6)
            XCTAssertLessThanOrEqual(layout.labelPoint.x, 114)
            XCTAssertGreaterThanOrEqual(layout.labelPoint.y, 6)
            XCTAssertLessThanOrEqual(layout.labelPoint.y, 52)
        }
    }

    func testAlertSoundResourcesAreBundled() throws {
        let risingURL = try XCTUnwrap(AlertSoundPlayer.resourceURL(for: .rising))
        let fallingURL = try XCTUnwrap(AlertSoundPlayer.resourceURL(for: .falling))

        XCTAssertEqual(risingURL.lastPathComponent, "bull-moo.wav")
        XCTAssertEqual(fallingURL.lastPathComponent, "bear-growl.wav")
    }

    func testStorageStatusTakesPriorityOverSourceStatus() {
        XCTAssertNil(
            MonitorStatusIndicator(sourceError: nil, storageError: nil)
        )
        XCTAssertEqual(
            MonitorStatusIndicator(sourceError: "网络不可用", storageError: nil),
            .source("网络不可用")
        )
        XCTAssertEqual(
            MonitorStatusIndicator(
                sourceError: "网络不可用",
                storageError: "数据库不可写"
            ),
            .storage("数据库不可写")
        )
    }
}
