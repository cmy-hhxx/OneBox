import Foundation

/// Caches optional source artwork separately from the three media-importing
/// operations. Artwork is best-effort metadata: a failed thumbnail must never
/// stop a user from importing or playing the audio itself.
protocol ArtworkCaching: Sendable {
    func cacheArtwork(from url: URL, to destinationURL: URL) async throws
}

actor ArtworkDownloader: ArtworkCaching {
    private static let maximumArtworkBytes = 10 * 1_024 * 1_024
    private let transport: URLSessionHTTPTransport

    init(session: URLSession = .shared) {
        transport = URLSessionHTTPTransport(session: session)
    }

    func cacheArtwork(from url: URL, to destinationURL: URL) async throws {
        guard url.scheme?.lowercased() == "https", url.host != nil else {
            throw ArtworkDownloadError.invalidURL
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        let result: HTTPTransportResponse
        do {
            result = try await transport.data(for: request, redirectValidator: Self.acceptsRedirect)
        } catch ContentImportError.cancelled {
            throw ArtworkDownloadError.cancelled
        } catch {
            throw ArtworkDownloadError.invalidResponse
        }
        guard (200..<300).contains(result.response.statusCode),
            result.response.mimeType?.lowercased().hasPrefix("image/") == true,
            result.data.count <= Self.maximumArtworkBytes,
            !result.data.isEmpty
        else {
            if result.data.count > Self.maximumArtworkBytes {
                throw ArtworkDownloadError.responseTooLarge
            }
            throw ArtworkDownloadError.invalidResponse
        }

        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try result.data.write(to: destinationURL, options: .atomic)
    }

    private static func acceptsRedirect(from original: URL, to redirected: URL) -> Bool {
        original.scheme?.lowercased() == "https"
            && redirected.scheme?.lowercased() == "https"
            && original.host?.lowercased() == redirected.host?.lowercased()
    }
}

private enum ArtworkDownloadError: Error {
    case invalidURL
    case invalidResponse
    case responseTooLarge
    case cancelled
}
