import Foundation
import XCTest

@testable import PodPinTool

final class HTTPTransportTests: XCTestCase {
    func testDownloadPreservesTemporaryFileAfterSessionCompletion() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DownloadURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let transport = URLSessionHTTPTransport(session: session)

        let response = try await transport.download(
            for: URLRequest(url: URL(string: "https://example.com/audio.mp3")!),
            progress: { _ in }
        )
        defer { try? FileManager.default.removeItem(at: response.temporaryURL) }

        XCTAssertEqual(try Data(contentsOf: response.temporaryURL), DownloadURLProtocol.payload)
    }
}

private final class DownloadURLProtocol: URLProtocol, @unchecked Sendable {
    static let payload = Data(repeating: 0x2A, count: 4_096)

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Length": String(Self.payload.count)]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.payload)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
