import Foundation
import os

final class StubURLProtocol: URLProtocol {
    typealias Handler = @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
    typealias RedirectHandler =
        @Sendable (URLRequest) -> (request: URLRequest, response: HTTPURLResponse)?

    private static let handlerStorage = OSAllocatedUnfairLock<Handler?>(initialState: nil)
    private static let redirectHandlerStorage = OSAllocatedUnfairLock<RedirectHandler?>(
        initialState: nil
    )

    static var handler: Handler? {
        get { handlerStorage.withLock { $0 } }
        set { handlerStorage.withLock { $0 = newValue } }
    }

    static var redirectHandler: RedirectHandler? {
        get { redirectHandlerStorage.withLock { $0 } }
        set { redirectHandlerStorage.withLock { $0 = newValue } }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        if let redirect = Self.redirectHandler?(request) {
            client?.urlProtocol(
                self,
                wasRedirectedTo: redirect.request,
                redirectResponse: redirect.response
            )
            return
        }

        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
