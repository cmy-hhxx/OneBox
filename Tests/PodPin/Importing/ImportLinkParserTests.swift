import XCTest

@testable import PodPinTool

final class ImportLinkParserTests: XCTestCase {
    func testRecognisesFiresideEpisodeLink() {
        let candidates = ImportLinkParser.candidates(
            in: "https://sv101.fireside.fm/260"
        )

        XCTAssertEqual(
            candidates.urls,
            [URL(string: "https://sv101.fireside.fm/260")!]
        )
    }

    func testRecognisesXiaoyuzhouEpisodeLink() {
        let candidates = ImportLinkParser.candidates(
            in: "https://www.xiaoyuzhoufm.com/episode/6a75424b000a55a9bb042560"
        )

        XCTAssertEqual(
            candidates.urls,
            [URL(string: "https://www.xiaoyuzhoufm.com/episode/6a75424b000a55a9bb042560")!]
        )
    }
    func testExtractsPublicURLFromCompleteDouyinSharePhrase() {
        let text =
            "2.58 复制打开抖音，看看【趋势天哥的作品】韩国指数暴跌探底回升，全球科技企稳了吗？ # A股... https://v.douyin.com/Ne1f5EXZW4Q/ :8pm B@G.IV Wmd:/ 10/20"

        let candidates = ImportLinkParser.candidates(in: text)

        XCTAssertEqual(candidates.urls, [URL(string: "https://v.douyin.com/Ne1f5EXZW4Q/")!])
        XCTAssertEqual(candidates.detectedHTTPSURLCount, 1)
        XCTAssertEqual(candidates.suggestedTitle, "韩国指数暴跌探底回升，全球科技企稳了吗？")
    }

    func testExtractsTitleFromUserReportedDouyinSharePhrase() {
        let text =
            "8.41 10/28 qEU:/ :7pm u@f.Bg 全英Talk｜为什么拥有的资源少，反而能走得更远？ # 英语口语 # 自我成长 # 人生智慧 # 大学生就业 # 每日英语听力  https://v.douyin.com/25Kk0YvJFw0/ 复制此链接，打开Dou音搜索，直接观看视频！"

        let candidates = ImportLinkParser.candidates(in: text)

        XCTAssertEqual(candidates.urls, [URL(string: "https://v.douyin.com/25Kk0YvJFw0/")!])
        XCTAssertEqual(candidates.suggestedTitle, "全英Talk｜为什么拥有的资源少，反而能走得更远？")
    }

    func testTrimsSharePunctuationAndDeDuplicatesURLsInFirstSeenOrder() {
        let text =
            "看看 https://www.bilibili.com/video/BV1xx411c7mD。再看 https://www.bilibili.com/video/BV1xx411c7mD#share"

        let candidates = ImportLinkParser.candidates(in: text)

        XCTAssertEqual(candidates.urls.count, 1)
        XCTAssertEqual(
            candidates.urls.first?.absoluteString, "https://www.bilibili.com/video/BV1xx411c7mD")
        XCTAssertEqual(candidates.detectedHTTPSURLCount, 2)
    }

    func testRetainsMultipleSupportedLinksForAFutureBatchQueue() {
        let text = "https://v.douyin.com/Ne1f5EXZW4Q/ https://www.bilibili.com/video/BV1xx411c7mD"

        let candidates = ImportLinkParser.candidates(in: text)

        XCTAssertEqual(candidates.urls.map(\.host), ["v.douyin.com", "www.bilibili.com"])
        XCTAssertFalse(candidates.hasExactlyOneSupportedURL)
    }

    func testFiltersUnsupportedAndNonHTTPSLinks() {
        let text = "http://www.bilibili.com/video/BV1xx411c7mD https://example.com/a"

        let candidates = ImportLinkParser.candidates(in: text)

        XCTAssertTrue(candidates.urls.isEmpty)
        XCTAssertEqual(candidates.detectedHTTPSURLCount, 1)
    }
}
