import Foundation
import XCTest

@testable import PodPinTool

final class BilibiliContentImporterTests: XCTestCase {
    func testPublicMultipartVideoDiscoversAllPagesAndResolvesAACWithoutAuthentication() async throws
    {
        let sourceURL = URL(
            string:
                "https://www.bilibili.com/video/BV1MN4dewEQZ/?spm_id_from=333.337.search-card.all.click"
        )!
        let transport = BilibiliFixtureTransport(bvid: "BV1MN4dewEQZ", pageCount: 26)
        let importer = PodPinContentImporter(
            sourceAdapters: [BilibiliContentAdapter(transport: transport)]
        )

        let discovery = try await importer.probe(url: sourceURL)
        let stream = try await importer.resolveStream(for: discovery.primaryItem)

        XCTAssertEqual(discovery.items.count, 26)
        XCTAssertEqual(discovery.groupTitle, "韩国指数暴跌探底回升")
        XCTAssertEqual(
            discovery.items.map(\.contentID),
            (1...26).map { "BV1MN4dewEQZ_p\($0)" }
        )
        XCTAssertEqual(
            discovery.items.first?.sourceURL.absoluteString,
            "https://www.bilibili.com/video/BV1MN4dewEQZ?p=1")
        XCTAssertEqual(
            discovery.items.last?.sourceURL.absoluteString,
            "https://www.bilibili.com/video/BV1MN4dewEQZ?p=26")
        XCTAssertEqual(stream.url.absoluteString, "https://audio.bilivideo.com/high.m4s")
        XCTAssertEqual(stream.headers["Referer"], "https://www.bilibili.com/")
        XCTAssertEqual(stream.mimeType, "audio/mp4")
        XCTAssertEqual(discovery.primaryItem.artworkURL?.scheme, "https")
    }

    func testExplicitPageDiscoversOnlyThatPart() async throws {
        let sourceURL = URL(string: "https://www.bilibili.com/video/BV1MN4dewEQZ?p=7")!
        let importer = PodPinContentImporter(
            sourceAdapters: [
                BilibiliContentAdapter(
                    transport: BilibiliFixtureTransport(bvid: "BV1MN4dewEQZ", pageCount: 26)
                )
            ]
        )

        let discovery = try await importer.probe(url: sourceURL)

        XCTAssertEqual(discovery.items.map(\.contentID), ["BV1MN4dewEQZ_p7"])
        XCTAssertFalse(discovery.isCollection)
    }

    func testHTTP412IsPlatformUnavailableRatherThanBrowserAccess() async throws {
        let sourceURL = URL(string: "https://www.bilibili.com/video/BV1MN4dewEQZ")!
        let importer = PodPinContentImporter(
            sourceAdapters: [
                BilibiliContentAdapter(
                    transport: BilibiliFixtureTransport(
                        bvid: "BV1MN4dewEQZ",
                        pageCount: 26,
                        responseStatus: 412
                    )
                )
            ]
        )

        do {
            _ = try await importer.probe(url: sourceURL)
            XCTFail("Expected Bilibili 412 to fail")
        } catch ContentImportError.platformUnavailable {
            // Expected: this is public API rate limiting, not authentication.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testB23RedirectOutsideBilibiliIsRejected() async throws {
        let sourceURL = URL(string: "https://b23.tv/public-id")!
        let adapter = BilibiliContentAdapter(
            transport: BilibiliShortLinkTransport(
                finalURL: URL(string: "https://attacker.example/video/BV1MN4dewEQZ")!
            )
        )

        do {
            _ = try await adapter.probe(url: sourceURL, attempt: .anonymous)
            XCTFail("A third-party short-link redirect must be rejected")
        } catch ContentImportError.platformUnavailable {
            // Expected.
        }
    }
}

private struct BilibiliShortLinkTransport: HTTPTransporting {
    let finalURL: URL

    func data(for request: URLRequest) async throws -> HTTPTransportResponse {
        let response = HTTPURLResponse(
            url: finalURL,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!
        return HTTPTransportResponse(data: Data(), response: response)
    }
}

private actor BilibiliFixtureTransport: HTTPTransporting {
    let bvid: String
    let pageCount: Int
    let responseStatus: Int

    init(bvid: String, pageCount: Int, responseStatus: Int = 200) {
        self.bvid = bvid
        self.pageCount = pageCount
        self.responseStatus = responseStatus
    }

    func data(for request: URLRequest) async throws -> HTTPTransportResponse {
        let url = try XCTUnwrap(request.url)
        if responseStatus != 200 {
            let response = try XCTUnwrap(
                HTTPURLResponse(
                    url: url,
                    statusCode: responseStatus,
                    httpVersion: "HTTP/1.1",
                    headerFields: nil
                )
            )
            return HTTPTransportResponse(data: Data(), response: response)
        }
        let object: [String: Any]
        if url.path == "/x/web-interface/view" {
            object = [
                "code": 0,
                "data": [
                    "bvid": bvid,
                    "title": "韩国指数暴跌探底回升",
                    "pic": "http://i2.hdslb.com/cover.jpg",
                    "duration": 2600,
                    "state": 0,
                    "owner": ["name": "作者"],
                    "rights": ["pay": 0, "arc_pay": 0],
                    "pages": (1...pageCount).map { page in
                        ["cid": 10_000 + page, "page": page, "part": "第\(page)部分", "duration": 100]
                    },
                ],
            ]
        } else if url.path == "/x/player/playurl" {
            object = [
                "code": 0,
                "data": [
                    "dash": [
                        "audio": [
                            [
                                "id": 30216,
                                "baseUrl": "https://audio.bilivideo.com/low.m4s",
                                "bandwidth": 64000,
                                "mimeType": "audio/mp4",
                                "codecs": "mp4a.40.2",
                            ],
                            [
                                "id": 30280,
                                "baseUrl": "https://audio.bilivideo.com/high.m4s",
                                "bandwidth": 192000,
                                "mimeType": "audio/mp4",
                                "codecs": "mp4a.40.2",
                            ],
                        ]
                    ]
                ],
            ]
        } else {
            throw ContentImportError.malformedResponse
        }

        let response = try XCTUnwrap(
            HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)
        )
        return HTTPTransportResponse(
            data: try JSONSerialization.data(withJSONObject: object),
            response: response
        )
    }
}
