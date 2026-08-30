import Foundation
import XCTest

@testable import PodPinTool

final class SupportedSourceTests: XCTestCase {

    func testVerificationNavigationStaysOnTheRequestedPlatform() {
        XCTAssertTrue(
            SupportedSource.douyin.acceptsVerificationNavigation(
                to: URL(string: "https://www.douyin.com/video/123")!
            )
        )
        XCTAssertFalse(
            SupportedSource.douyin.acceptsVerificationNavigation(
                to: URL(string: "https://example.com/challenge")!
            )
        )
        XCTAssertFalse(
            SupportedSource.douyin.acceptsVerificationNavigation(
                to: URL(string: "https://www.bilibili.com/video/BV1xx411c7mD")!
            )
        )
    }
    func testRecognisesSupportedSingleItemHosts() throws {
        XCTAssertEqual(
            try SupportedSource.validateSinglePublicItem(
                url: URL(string: "https://www.bilibili.com/video/BV1xx411c7mD")!
            ),
            .bilibili
        )
        XCTAssertEqual(
            try SupportedSource.validateSinglePublicItem(
                url: URL(string: "https://v.douyin.com/example/")!
            ),
            .douyin
        )
        XCTAssertEqual(
            try SupportedSource.validateSinglePublicItem(
                url: URL(string: "https://b23.tv/example")!
            ),
            .bilibili
        )
        XCTAssertEqual(
            try SupportedSource.validateSinglePublicItem(
                url: URL(string: "https://www.xiaoyuzhoufm.com/episode/6a75424b000a55a9bb042560")!
            ),
            .xiaoyuzhou
        )
        XCTAssertEqual(
            try SupportedSource.validateSinglePublicItem(
                url: URL(string: "https://sv101.fireside.fm/260")!
            ),
            .fireside
        )
    }

    func testRejectsNonHTTPSAndCollectionURLsBeforeLaunchingTool() {
        XCTAssertThrowsError(
            try SupportedSource.validateSinglePublicItem(
                url: URL(string: "http://www.bilibili.com/video/BV1xx411c7mD")!
            )
        )
        XCTAssertThrowsError(
            try SupportedSource.validateSinglePublicItem(
                url: URL(string: "https://www.bilibili.com/medialist/play/123")!
            )
        )
        XCTAssertThrowsError(
            try SupportedSource.validateSinglePublicItem(
                url: URL(string: "https://www.douyin.com/user/123")!
            )
        )
    }

    func testRejectsHomeQueryOnlyAndMalformedShortLinks() {
        let rejectedURLs = [
            "https://www.bilibili.com/",
            "https://www.bilibili.com/?bvid=BV1xx411c7mD",
            "https://www.bilibili.com/video/",
            "https://b23.tv/",
            "https://b23.tv/video/BV1xx411c7mD",
            "https://www.douyin.com/",
            "https://www.douyin.com/video/",
            "https://v.douyin.com/",
            "https://v.douyin.com/video/example",
            "https://v.douyin.com/example/extra",
            "https://sv101.fireside.fm/",
            "https://sv101.fireside.fm/episodes",
            "https://sv101.fireside.fm/260/extra",
            "https://aphid.fireside.fm/example.mp3",
        ]

        for sourceURL in rejectedURLs {
            XCTAssertThrowsError(
                try SupportedSource.validateSinglePublicItem(url: URL(string: sourceURL)!),
                "should reject \(sourceURL)"
            )
        }
    }
}
