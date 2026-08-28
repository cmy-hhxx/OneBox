import Foundation

/// Internal source seam. Store and UI only use `ContentImporting`; platform
/// response shapes and refresh rules remain local to their adapter.
protocol ContentSourceAdapter: Sendable {
    var source: SupportedSource { get }

    func probe(url: URL, attempt: ImportAttempt) async throws -> ImportDiscovery
    func resolveStream(
        for content: ImportedAudioMetadata,
        attempt: ImportAttempt
    ) async throws -> ResolvedAudioStream
}
