import Foundation
import XCTest

@testable import PodPinTool

final class FiresideContentImporterTests: XCTestCase {
    func testPublicEpisodeUsesPodcastScopedIdentityAndFreshMediaURL() async throws {
        let sourceURL = URL(string: "https://sv101.fireside.fm/260")!
        let redirectedAudioURL = URL(
            string: "https://media24.fireside.fm/file/fireside-audio-2024/episode.mp3"
        )!
        let transport = FiresideFixtureTransport(
            sourceURL: sourceURL,
            redirectedAudioURL: redirectedAudioURL,
            body: Self.episodeHTML
        )
        let importer = PodPinContentImporter(
            sourceAdapters: [FiresideContentAdapter(transport: transport)]
        )

        let discovery = try await importer.probe(url: sourceURL)
        let item = discovery.primaryItem
        let stream = try await importer.resolveStream(for: item)

        XCTAssertEqual(discovery.items.count, 1)
        XCTAssertEqual(item.platform, .fireside)
        XCTAssertEqual(item.contentID, "sv101.fireside.fm/260")
        XCTAssertEqual(item.sourceURL, sourceURL)
        XCTAssertEqual(item.title, "E247｜对话盛颖：xAI 与 SGLang")
        XCTAssertEqual(item.author, "硅谷101")
        XCTAssertEqual(item.duration, 6_386)
        XCTAssertEqual(
            item.artworkURL?.absoluteString,
            "https://media24.fireside.fm/file/fireside-images-2024/cover_medium.jpg"
        )
        XCTAssertEqual(stream.url, redirectedAudioURL)
        XCTAssertEqual(stream.headers["Referer"], sourceURL.absoluteString)
        XCTAssertEqual(stream.mimeType, "audio/mpeg")
    }

    func testRejectsJSONLDForAnotherEpisode() async throws {
        let sourceURL = URL(string: "https://sv101.fireside.fm/259")!
        let adapter = FiresideContentAdapter(
            transport: FiresideFixtureTransport(
                sourceURL: sourceURL,
                redirectedAudioURL: URL(string: "https://media24.fireside.fm/episode.mp3")!,
                body: Self.episodeHTML
            ))

        await assertThrowsErrorAsync(
            try await adapter.probe(url: sourceURL, attempt: .anonymous)
        ) { error in
            XCTAssertEqual(error as? ContentImportError, .contentChanged)
        }
    }

    private static let episodeHTML = #"""
        <html><head>
          <script type="application/ld+json">{
            "@context":"https://schema.org",
            "@type":"PodcastEpisode",
            "name":"E247｜对话盛颖：xAI 与 SGLang",
            "url":"https://sv101.fireside.fm/260",
            "timeRequired":"PT1H46M26S",
            "image":"https://media24.fireside.fm/file/fireside-images-2024/cover_medium.jpg",
            "associatedMedia":{
              "@type":"MediaObject",
              "contentUrl":"https://aphid.fireside.fm/d/example/episode.mp3"
            },
            "partOfSeries":{
              "@type":"PodcastSeries",
              "name":"硅谷101",
              "url":"https://sv101.fireside.fm"
            }
          }</script>
        </head></html>
        """#
}

private struct FiresideFixtureTransport: HTTPTransporting {
    let sourceURL: URL
    let redirectedAudioURL: URL
    let body: String

    func data(for request: URLRequest) async throws -> HTTPTransportResponse {
        let isHeadRequest = request.httpMethod == "HEAD"
        let response = try XCTUnwrap(
            HTTPURLResponse(
                url: isHeadRequest ? redirectedAudioURL : sourceURL,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: [
                    "Content-Type": isHeadRequest ? "audio/mpeg" : "text/html; charset=utf-8"
                ]
            ))
        return HTTPTransportResponse(data: Data(body.utf8), response: response)
    }
}

private func assertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    _ errorHandler: (Error) -> Void = { _ in }
) async {
    do {
        _ = try await expression()
        XCTFail("Expected expression to throw")
    } catch {
        errorHandler(error)
    }
}
