import Foundation
import XCTest

@testable import PodPinTool

final class XiaoyuzhouContentImporterTests: XCTestCase {
    func testPublicEpisodeUsesStableEpisodeIdentityAndFreshMediaURL() async throws {
        let sourceURL = URL(
            string: "https://www.xiaoyuzhoufm.com/episode/6a75424b000a55a9bb042560")!
        let transport = StaticHTTPTransport(
            url: sourceURL,
            body: """
                <html><body>
                <script id="__NEXT_DATA__" type="application/json">{
                  "props":{"pageProps":{"episode":{
                    "type":"EPISODE",
                    "eid":"6a75424b000a55a9bb042560",
                    "title":"从蒸馏到合成数据到 RSI",
                    "duration":3569,
                    "enclosure":{"url":"https://media.xyzcdn.net/podcast/fresh.m4a"},
                    "isPrivateMedia":false,
                    "status":"NORMAL",
                    "image":{"picture":{"picUrl":"https://image.xyzcdn.net/cover.png"}},
                    "podcast":{"title":"42章经"}
                  }}},
                  "page":"/episode/[id]"
                }</script>
                </body></html>
                """
        )
        let importer = PodPinContentImporter(
            sourceAdapters: [XiaoyuzhouContentAdapter(transport: transport)]
        )

        let discovery = try await importer.probe(url: sourceURL)
        let item = discovery.primaryItem
        let stream = try await importer.resolveStream(for: item)

        XCTAssertEqual(discovery.items.count, 1)
        XCTAssertEqual(item.platform, .xiaoyuzhou)
        XCTAssertEqual(item.contentID, "6a75424b000a55a9bb042560")
        XCTAssertEqual(item.title, "从蒸馏到合成数据到 RSI")
        XCTAssertEqual(item.author, "42章经")
        XCTAssertEqual(item.duration, 3569)
        XCTAssertEqual(item.artworkURL?.absoluteString, "https://image.xyzcdn.net/cover.png")
        XCTAssertEqual(stream.url.absoluteString, "https://media.xyzcdn.net/podcast/fresh.m4a")
        XCTAssertEqual(stream.headers["Referer"], sourceURL.absoluteString)
    }

    func testJSONLDSupplementsPresentationFieldsMissingFromNextData() async throws {
        let sourceURL = URL(
            string: "https://www.xiaoyuzhoufm.com/episode/6a75424b000a55a9bb042560")!
        let transport = StaticHTTPTransport(
            url: sourceURL,
            body: """
                <html><body>
                <script type="application/ld+json">{
                  "@context":"https://schema.org",
                  "@type":"PodcastEpisode",
                  "name":"JSON-LD 标题不应覆盖 Next 标题",
                  "image":"https://image.xyzcdn.net/jsonld-cover.png",
                  "partOfSeries":{"@type":"PodcastSeries","name":"42章经"}
                }</script>
                <script id="__NEXT_DATA__" type="application/json">{
                  "props":{"pageProps":{"episode":{
                    "type":"EPISODE",
                    "eid":"6a75424b000a55a9bb042560",
                    "title":"Next 标题",
                    "duration":3569,
                    "enclosure":{"url":"https://media.xyzcdn.net/podcast/fresh.m4a"},
                    "isPrivateMedia":false,
                    "status":"NORMAL",
                    "podcast":{}
                  }}},
                  "page":"/episode/[id]"
                }</script>
                </body></html>
                """
        )
        let adapter = XiaoyuzhouContentAdapter(transport: transport)

        let discovery = try await adapter.probe(url: sourceURL, attempt: .anonymous)

        XCTAssertEqual(discovery.primaryItem.title, "Next 标题")
        XCTAssertEqual(discovery.primaryItem.author, "42章经")
        XCTAssertEqual(
            discovery.primaryItem.artworkURL?.absoluteString,
            "https://image.xyzcdn.net/jsonld-cover.png"
        )
    }
}

private struct StaticHTTPTransport: HTTPTransporting {
    let url: URL
    let body: String

    func data(for request: URLRequest) async throws -> HTTPTransportResponse {
        let responseURL = request.httpMethod == "HEAD" ? request.url! : url
        let response = try XCTUnwrap(
            HTTPURLResponse(
                url: responseURL,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "text/html"]
            )
        )
        return HTTPTransportResponse(data: Data(body.utf8), response: response)
    }
}
