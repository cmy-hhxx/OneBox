import CoreGraphics
import XCTest

@testable import PodPinTool

final class NowPlayingLayoutMetricsTests: XCTestCase {
    func testPlayerFitsBesideQueueAtMinimumWindowWidth() {
        // Minimum window, host sidebar/insets, queue, and player padding.
        for queueWidth: CGFloat in [280, 320, 360] {
            let available = CGSize(
                width: 556 * 1048 / 648 - 224 - 48 - queueWidth - 32, height: 360)
            let metrics = NowPlayingLayoutMetrics(availableSize: available)
            XCTAssertLessThanOrEqual(metrics.contentWidth, available.width)
            XCTAssertLessThanOrEqual(metrics.artworkSize, metrics.contentWidth)
        }
    }
}
