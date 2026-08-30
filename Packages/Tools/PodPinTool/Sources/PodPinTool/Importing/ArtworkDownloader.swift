import Foundation

/// Caches optional source artwork separately from the three media-importing
/// operations. Artwork is best-effort metadata: a failed thumbnail must never
/// stop a user from importing or playing the audio itself.
protocol ArtworkCaching: Sendable {
    func cacheArtwork(from url: URL, to destinationURL: URL) async throws
}

actor ArtworkDownloader: ArtworkCaching {
    private static let maximumArtworkBytes = 10 * 1_024 * 1_024

    func cacheArtwork(from url: URL, to destinationURL: URL) async throws {
        guard url.scheme?.lowercased() == "https" else { throw ArtworkDownloadError.invalidURL }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let response = response as? HTTPURLResponse,
            (200..<300).contains(response.statusCode),
            response.mimeType?.lowercased().hasPrefix("image/") == true,
            response.expectedContentLength <= Int64(Self.maximumArtworkBytes)
                || response.expectedContentLength == NSURLSessionTransferSizeUnknown
        else { throw ArtworkDownloadError.invalidResponse }

        var data = Data()
        for try await byte in bytes {
            guard data.count < Self.maximumArtworkBytes else {
                throw ArtworkDownloadError.responseTooLarge
            }
            data.append(byte)
        }
        guard !data.isEmpty else { throw ArtworkDownloadError.invalidResponse }

        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: destinationURL, options: .atomic)
    }
}

private enum ArtworkDownloadError: Error {
    case invalidURL
    case invalidResponse
    case responseTooLarge
}
