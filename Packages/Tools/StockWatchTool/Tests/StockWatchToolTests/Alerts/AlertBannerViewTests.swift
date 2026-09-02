import OneBoxDesignSystem
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

    @MainActor
    func testInspectorUsesTheSharedDockedWidth() {
        XCTAssertEqual(DesignMetrics.inspectorWidth, 248)
    }
}
