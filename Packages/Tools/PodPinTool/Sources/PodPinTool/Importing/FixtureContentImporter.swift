import Foundation

/// Deterministic importer used by debug builds and unit tests.
/// It is intentionally opt-in: production URLs still flow to platform adapters.
actor FixtureContentImporter: ContentImporting {
    static let sampleURL = URL(string: "https://fixture.podpin.local/welcome")!
    static let collectionSampleURL = URL(string: "https://fixture.podpin.local/collection")!

    private let audioURL: URL

    init(audioURL: URL) {
        self.audioURL = audioURL
    }

    func probe(url: URL, attempt: ImportAttempt) async throws -> ImportDiscovery {
        guard url.host == Self.sampleURL.host else { throw ContentImportError.unsupportedURL }
        if url.path == Self.collectionSampleURL.path {
            let items = (1...3).map { index in
                ImportedAudioMetadata(
                    platform: .fixture,
                    contentID: "collection-part-\(index)",
                    sourceURL: Self.collectionSampleURL,
                    title: "PodPin 示例分段 \(index)",
                    author: "PodPin",
                    artworkURL: nil,
                    duration: 8
                )
            }
            return ImportDiscovery(
                sourceURL: Self.collectionSampleURL,
                groupTitle: "PodPin 示例合集",
                primaryItem: items[0],
                remainingItems: Array(items.dropFirst())
            )
        }
        let metadata = ImportedAudioMetadata(
            platform: .fixture,
            contentID: "welcome",
            sourceURL: Self.sampleURL,
            title: "PodPin 示例音频",
            author: "PodPin",
            artworkURL: nil,
            duration: 8
        )
        return ImportDiscovery(sourceURL: Self.sampleURL, primaryItem: metadata)
    }

    func resolveStream(
        for content: ImportedAudioMetadata,
        attempt: ImportAttempt
    ) async throws -> ResolvedAudioStream {
        guard content.platform == .fixture else { throw ContentImportError.unsupportedURL }
        return ResolvedAudioStream(url: audioURL, headers: [:], duration: content.duration)
    }

    func download(
        content: ImportedAudioMetadata,
        to destinationDirectory: URL,
        attempt: ImportAttempt,
        progress: @escaping @Sendable (DownloadProgressSnapshot) -> Void
    ) async throws -> DownloadedAudioFile {
        guard content.platform == .fixture else { throw ContentImportError.unsupportedURL }
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        let output = destinationDirectory.appendingPathComponent("audio.m4a")
        if fileManager.fileExists(atPath: output.path) {
            try fileManager.removeItem(at: output)
        }
        try fileManager.copyItem(at: audioURL, to: output)
        progress(.complete)
        return DownloadedAudioFile(url: output, duration: content.duration ?? 8)
    }
}

actor PodPinContentImporter: ContentImporting {
    private let fixture: FixtureContentImporter?
    private let fixtureFailure: ContentImportError?
    private let platformImporter: YTDLPContentImporter
    private let adapters: [SupportedSource: any ContentSourceAdapter]
    private let mediaMaterializer: any MediaMaterializing

    init(
        fixture: FixtureContentImporter? = nil,
        fixtureFailure: ContentImportError? = nil,
        toolLocator: BundledToolLocator = BundledToolLocator(toolsDirectoryURL: nil),
        platformImporter: YTDLPContentImporter? = nil,
        anonymousSession: (any AnonymousSessionProviding)? = nil,
        sourceAdapters: [any ContentSourceAdapter]? = nil,
        mediaMaterializer: (any MediaMaterializing)? = nil
    ) {
        self.fixture = fixture
        self.fixtureFailure = fixtureFailure
        self.platformImporter =
            platformImporter
            ?? YTDLPContentImporter(
                toolLocator: toolLocator,
                anonymousSession: anonymousSession
            )
        let resolvedAdapters =
            sourceAdapters ?? [
                BilibiliContentAdapter(),
                DouyinContentAdapter(),
                FiresideContentAdapter(),
                XiaoyuzhouContentAdapter(),
            ]
        adapters = Dictionary(uniqueKeysWithValues: resolvedAdapters.map { ($0.source, $0) })
        self.mediaMaterializer =
            mediaMaterializer ?? MediaMaterializer(toolLocator: toolLocator)
    }

    func probe(url: URL, attempt: ImportAttempt) async throws -> ImportDiscovery {
        if url.host == FixtureContentImporter.sampleURL.host {
            return try await fixtureOrThrow().probe(url: url, attempt: attempt)
        }
        if let source = SupportedSource.source(for: url), let adapter = adapters[source] {
            return try await adapter.probe(url: url, attempt: attempt)
        }
        return try await platformImporter.probe(url: url, attempt: attempt)
    }

    func resolveStream(
        for content: ImportedAudioMetadata,
        attempt: ImportAttempt
    ) async throws -> ResolvedAudioStream {
        if content.platform == .fixture {
            return try await fixtureOrThrow().resolveStream(for: content, attempt: attempt)
        }
        if let source = SupportedSource.source(for: content.sourceURL),
            let adapter = adapters[source]
        {
            return try await adapter.resolveStream(for: content, attempt: attempt)
        }
        return try await platformImporter.resolveStream(for: content, attempt: attempt)
    }

    func download(
        content: ImportedAudioMetadata,
        to destinationDirectory: URL,
        attempt: ImportAttempt,
        progress: @escaping @Sendable (DownloadProgressSnapshot) -> Void
    ) async throws -> DownloadedAudioFile {
        if content.platform == .fixture {
            return try await fixtureOrThrow().download(
                content: content,
                to: destinationDirectory,
                attempt: attempt,
                progress: progress
            )
        }
        if let source = SupportedSource.source(for: content.sourceURL),
            let adapter = adapters[source]
        {
            let stream = try await adapter.resolveStream(for: content, attempt: attempt)
            return try await mediaMaterializer.materialize(
                stream: stream,
                to: destinationDirectory,
                progress: progress
            )
        }
        return try await platformImporter.download(
            content: content, to: destinationDirectory, attempt: attempt, progress: progress)
    }

    private func fixtureOrThrow() throws -> FixtureContentImporter {
        guard let fixture else {
            throw fixtureFailure ?? .mediaUnavailable("示例音频不可用，请重新安装 PodPin。")
        }
        return fixture
    }
}
