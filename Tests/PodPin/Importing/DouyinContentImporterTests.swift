import Foundation
import XCTest

@testable import PodPinTool

final class DouyinContentImporterTests: XCTestCase {
    func testRenderedPublicVideoUsesCanonicalIdentityAndUniqueMainAudio() async throws {
        let sourceURL = URL(string: "https://v.douyin.com/Ne1f5EXZW4Q/")!
        let canonicalURL = URL(string: "https://www.douyin.com/video/7667887133545205043")!
        let loader = StaticRenderedPageLoader(
            page: DouyinRenderedPage(
                canonicalURL: canonicalURL,
                title: "韩国指数暴跌探底回升，全球科技企稳了吗？ #A股 #股票 #财经 #科技 #韩国",
                author: "趋势天哥",
                artworkURL: URL(string: "https://p3-sign.douyinpic.com/cover.jpeg"),
                duration: 357.834,
                audioURL: URL(string: "https://v3.douyinvod.com/media-audio-und-mp4a/sample.mp4")!,
                userAgent: "PodPin WebKit",
                cookies: []
            )
        )
        let importer = PodPinContentImporter(
            sourceAdapters: [DouyinContentAdapter(pageLoader: loader)]
        )

        let discovery = try await importer.probe(url: sourceURL)
        let stream = try await importer.resolveStream(for: discovery.primaryItem)

        XCTAssertEqual(discovery.primaryItem.contentID, "7667887133545205043")
        XCTAssertEqual(discovery.primaryItem.author, "趋势天哥")
        XCTAssertEqual(discovery.primaryItem.duration, 357.834)
        XCTAssertEqual(discovery.primaryItem.sourceURL, canonicalURL)
        XCTAssertEqual(
            stream.url.absoluteString, "https://v3.douyinvod.com/media-audio-und-mp4a/sample.mp4")
        XCTAssertEqual(stream.headers["Referer"], canonicalURL.absoluteString)
        XCTAssertEqual(stream.headers["User-Agent"], "PodPin WebKit")
    }
}

private struct StaticRenderedPageLoader: DouyinRenderedPageLoading {
    let page: DouyinRenderedPage

    func load(url: URL, cookies: [HTTPCookie]) async throws -> DouyinRenderedPage {
        page
    }
}
