import XCTest

@testable import PodPinTool

final class DownloadSpeedSamplerTests: XCTestCase {
    func testReportsBytesPerSecondFromMonotonicSamples() throws {
        var sampler = DownloadSpeedSampler()

        XCTAssertNil(sampler.sample(completedBytes: 1_000, at: 10))
        XCTAssertEqual(
            try XCTUnwrap(sampler.sample(completedBytes: 501_000, at: 10.5)),
            1_000_000,
            accuracy: 0.001
        )
    }

    func testProgressScalingKeepsTransferSpeed() {
        let progress = DownloadProgressSnapshot(fraction: 0.5, bytesPerSecond: 2_000_000)

        XCTAssertEqual(progress.scaled(to: 0.9).fraction, 0.45)
        XCTAssertEqual(progress.scaled(to: 0.9).bytesPerSecond, 2_000_000)
    }
}
