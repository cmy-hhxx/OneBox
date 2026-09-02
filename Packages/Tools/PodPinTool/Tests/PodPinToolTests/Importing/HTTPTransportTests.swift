import Foundation
import XCTest
import os

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

    func testDownloadRejectsRedirectBeforeRequestingSecondHost() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RedirectingDownloadURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        RedirectingDownloadURLProtocol.requestedHosts.withLock { $0 = [] }
        let transport = URLSessionHTTPTransport(session: session)

        do {
            _ = try await transport.download(
                for: URLRequest(url: URL(string: "https://source.example/audio.mp3")!),
                redirectValidator: { _, _ in false },
                progress: { _ in }
            )
            XCTFail("Expected the rejected redirect to stop the download")
        } catch ContentImportError.malformedResponse {
            // The redirect response has no downloadable body once following is rejected.
        }
        XCTAssertEqual(
            RedirectingDownloadURLProtocol.requestedHosts.withLock { $0 },
            ["source.example"]
        )
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

private final class RedirectingDownloadURLProtocol: URLProtocol, @unchecked Sendable {
    static let requestedHosts = OSAllocatedUnfairLock<[String]>(initialState: [])

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let host = request.url?.host ?? "nil"
        Self.requestedHosts.withLock { $0.append(host) }
        guard host == "source.example" else {
            client?.urlProtocol(
                self,
                didFailWithError: URLError(.unsupportedURL)
            )
            return
        }
        let redirectedRequest = URLRequest(
            url: URL(string: "https://redirected.example/audio.mp3")!
        )
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 302,
            httpVersion: "HTTP/1.1",
            headerFields: ["Location": redirectedRequest.url!.absoluteString]
        )!
        client?.urlProtocol(
            self,
            wasRedirectedTo: redirectedRequest,
            redirectResponse: response
        )
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
