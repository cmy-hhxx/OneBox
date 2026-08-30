import XCTest

@testable import StockWatchTool

final class AlertBannerViewTests: XCTestCase {
    func testDismissalRemainsPausedForFocusedDescendantAfterPointerLeaves() {
        let state = AlertBannerDismissalState(
            isHovering: false,
            focusedElement: .descendantControl
        )

        XCTAssertTrue(state.isPaused)
    }

    func testDismissalResumesOnlyWhenNeitherPointerNorFocusIsInsideBanner() {
        XCTAssertTrue(
            AlertBannerDismissalState(
                isHovering: true,
                focusedElement: nil
            ).isPaused
        )
        XCTAssertTrue(
            AlertBannerDismissalState(
                isHovering: false,
                focusedElement: .banner
            ).isPaused
        )
        XCTAssertFalse(
            AlertBannerDismissalState(
                isHovering: false,
                focusedElement: nil
            ).isPaused
        )
    }

    func testAnnouncementPostsTheCurrentAccessibleMessageExactlyOnce() {
        let alert = AlertEvent(
            instrument: Instrument.initialWatchlist[0],
            changePercent: 4.25,
            lastPrice: 12.34,
            targetPrice: nil,
            basis: .percentage,
            direction: .rising,
            triggeredAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let announcement = AlertBannerAnnouncement(alert: alert)
        var messages: [String] = []

        announcement.post { messages.append($0) }

        XCTAssertEqual(messages, [announcement.message])
        XCTAssertTrue(messages[0].contains("上涨提醒"))
        XCTAssertTrue(messages[0].contains(alert.instrument.name))
    }

    func testAlertLayerAlwaysAppearsAboveInspectorAndMonitor() {
        XCTAssertLessThan(
            StockWatchWorkspaceLayer.monitor.zIndex,
            StockWatchWorkspaceLayer.inspector.zIndex
        )
        XCTAssertLessThan(
            StockWatchWorkspaceLayer.inspector.zIndex,
            StockWatchWorkspaceLayer.alert.zIndex
        )
    }

    @MainActor
    func testInspectorDocksOnlyAtSevenHundredPointsOrWider() {
        let compact = StockWatchWorkspaceLayout(availableWidth: 699).usesDockedInspector
        let docked = StockWatchWorkspaceLayout(availableWidth: 700).usesDockedInspector

        XCTAssertFalse(compact)
        XCTAssertTrue(docked)
    }

    @MainActor
    func testCompactInspectorWidthRemainsWithinItsSupportedBounds() {
        let minimum = StockWatchWorkspaceLayout(availableWidth: 320).compactInspectorWidth
        let maximum = StockWatchWorkspaceLayout(availableWidth: 699).compactInspectorWidth

        XCTAssertEqual(minimum, 320)
        XCTAssertEqual(maximum, 360)
    }
}
