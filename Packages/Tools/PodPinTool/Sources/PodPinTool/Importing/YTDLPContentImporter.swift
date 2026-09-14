import Foundation

/// Source adapter for the bundled `yt-dlp` and FFmpeg tools.
///
/// It accepts only the deliberately narrow Bilibili/Douyin URL contract in
/// `SupportedSource`; it does not carry cookies, logins, playlists, channel
/// pages or arbitrary extractor options. The store owns the non-reentrant
/// download gate, because an actor may yield while a subprocess is running.
actor YTDLPContentImporter: ContentImporting {
    /// Keep bundled `yt-dlp` independent from a user's configuration and
    /// plugins. These flags must precede every invocation that handles a URL.
    private static let isolatedYTDLPArguments = [
        "--ignore-config",
        "--no-plugin-dirs",
        "--no-playlist",
        "--no-warnings",
    ]

    private let runner: any ExternalToolRunning
    private let toolLocator: BundledToolLocator
    private let fileManager: FileManager
    private let anonymousSession: (any AnonymousSessionProviding)?

    init(
        runner: any ExternalToolRunning = ProcessToolRunner(),
        toolLocator: BundledToolLocator = BundledToolLocator(),
        fileManager: FileManager = .default,
        anonymousSession: (any AnonymousSessionProviding)? = nil
    ) {
        self.runner = runner
        self.toolLocator = toolLocator
        self.fileManager = fileManager
        self.anonymousSession = anonymousSession
    }

    func probe(url: URL, attempt: ImportAttempt) async throws -> ImportDiscovery {
        let expectedSource = try SupportedSource.validateSinglePublicItem(url: url)
        let tool = try toolLocator.executableURL(named: "yt-dlp")
        let result = try await runYTDLP(
            executableURL: tool,
            arguments: Self.isolatedYTDLPArguments + [
                "--skip-download",
                "--dump-single-json",
                "--",
                url.absoluteString,
            ],
            workingDirectoryURL: nil,
            source: expectedSource
        )
        try check(result, source: expectedSource)
        let payload = try decodePayload(result.standardOutput)
        try validate(payload: payload, expectedSource: expectedSource)
        guard let id = payload.id, !id.isEmpty,
            let title = payload.title?.trimmedNonEmpty
        else { throw ContentImportError.malformedToolOutput }

        let metadata = ImportedAudioMetadata(
            platform: expectedSource.platform,
            contentID: id,
            sourceURL: url,
            title: title,
            author: payload.uploader?.trimmedNonEmpty ?? payload.channel?.trimmedNonEmpty,
            artworkURL: payload.thumbnail.flatMap(URL.init(string:)),
            duration: payload.duration
        )
        return ImportDiscovery(sourceURL: url, primaryItem: metadata)
    }

    func resolveStream(
        for content: ImportedAudioMetadata,
        attempt: ImportAttempt
    ) async throws -> ResolvedAudioStream {
        let expectedSource = try expectedSource(for: content)
        let tool = try toolLocator.executableURL(named: "yt-dlp")
        let result = try await runYTDLP(
            executableURL: tool,
            arguments: Self.isolatedYTDLPArguments + [
                "--skip-download",
                "--dump-single-json",
                "-f",
                "bestaudio/best",
                "--",
                content.sourceURL.absoluteString,
            ],
            workingDirectoryURL: nil,
            source: expectedSource
        )
        try check(result, source: expectedSource)
        let payload = try decodePayload(result.standardOutput)
        try validate(payload: payload, expectedSource: expectedSource)
        guard payload.id == content.contentID,
            let streamURL = payload.url.flatMap(URL.init(string:))
        else {
            throw ContentImportError.mediaUnavailable("这个来源已无法提供可播放的音频，请稍后重试。")
        }
        return ResolvedAudioStream(
            url: streamURL,
            headers: payload.httpHeaders ?? [:],
            duration: payload.duration ?? content.duration
        )
    }

    func download(
        content: ImportedAudioMetadata,
        to destinationDirectory: URL,
        attempt: ImportAttempt,
        progress: @escaping @Sendable (DownloadProgressSnapshot) -> Void
    ) async throws -> DownloadedAudioFile {
        let expectedSource = try expectedSource(for: content)
        let tool = try toolLocator.executableURL(named: "yt-dlp")
        try await revalidateDownloadIdentity(
            of: content,
            expectedSource: expectedSource,
            tool: tool
        )
        let ffmpeg = try toolLocator.executableURL(named: "ffmpeg")
        let ffprobe = try toolLocator.executableURL(named: "ffprobe")
        let temporaryDirectory =
            destinationDirectory
            .appendingPathComponent(".download-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: temporaryDirectory) }

        let outputTemplate =
            temporaryDirectory
            .appendingPathComponent("audio.%(ext)")
            .path(percentEncoded: false)
        let result = try await runYTDLP(
            executableURL: tool,
            arguments: Self.isolatedYTDLPArguments + [
                "--extract-audio",
                "--audio-format",
                "m4a",
                "--audio-quality",
                "0",
                "-f",
                "bestaudio/best",
                "--ffmpeg-location",
                ffmpeg.deletingLastPathComponent().path,
                "--output",
                outputTemplate,
                "--print",
                "after_move:filepath",
                "--",
                content.sourceURL.absoluteString,
            ],
            workingDirectoryURL: temporaryDirectory,
            source: expectedSource
        )
        progress(result.terminationStatus == 0 ? .complete : .indeterminate)
        try check(result, source: expectedSource)

        guard
            let downloadedURL = outputPath(from: result.standardOutput, below: temporaryDirectory),
            fileManager.fileExists(atPath: downloadedURL.path)
        else { throw ContentImportError.invalidDownloadedAudio }

        let duration = try await validatedAudioDuration(of: downloadedURL, ffprobe: ffprobe)
        let finalURL = destinationDirectory.appendingPathComponent("audio.m4a")
        try fileManager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: finalURL.path) {
            try fileManager.removeItem(at: finalURL)
        }
        try fileManager.moveItem(at: downloadedURL, to: finalURL)
        return DownloadedAudioFile(url: finalURL, duration: duration)
    }

    private func check(_ result: ExternalToolResult, source: SupportedSource) throws {
        guard result.terminationStatus == 0 else {
            if Task.isCancelled { throw ContentImportError.cancelled }
            throw ContentImportFailure.toolFailure(
                result, tool: "yt-dlp",
                presentation: .platformUnavailable("\(source.displayName) 暂时无法解析这条公开内容，请稍后重试。")
            )
        }
    }

    private func runYTDLP(
        executableURL: URL,
        arguments: [String],
        workingDirectoryURL: URL?,
        source: SupportedSource
    ) async throws -> ExternalToolResult {
        let cookieFile = try await anonymousSession?.cookieFile(for: source)
        defer {
            if let cookieFile {
                try? fileManager.removeItem(at: cookieFile)
            }
        }

        var resolvedArguments = arguments
        if let cookieFile {
            resolvedArguments.insert(
                contentsOf: ["--cookies", cookieFile.path], at: Self.isolatedYTDLPArguments.count)
        }
        return try await runTool(
            executableURL: executableURL,
            arguments: resolvedArguments,
            workingDirectoryURL: workingDirectoryURL
        )
    }

    private func runTool(
        executableURL: URL,
        arguments: [String],
        workingDirectoryURL: URL?
    ) async throws -> ExternalToolResult {
        do {
            return try await runner.run(
                executableURL: executableURL,
                arguments: arguments,
                workingDirectoryURL: workingDirectoryURL
            )
        } catch is CancellationError {
            throw ContentImportError.cancelled
        }
    }

    private func decodePayload(_ output: String) throws -> YTDLPPayload {
        let decoder = JSONDecoder()
        guard
            let data =
                output
                .split(whereSeparator: \.isNewline)
                .reversed()
                .compactMap({ String($0).data(using: .utf8) })
                .first(where: { (try? decoder.decode(YTDLPPayload.self, from: $0)) != nil })
        else { throw ContentImportError.malformedToolOutput }
        return try decoder.decode(YTDLPPayload.self, from: data)
    }

    private func validate(payload: YTDLPPayload, expectedSource: SupportedSource) throws {
        let extractor = (payload.extractorKey ?? payload.extractor ?? "").lowercased()
        switch expectedSource {
        case .bilibili:
            guard extractor.contains("bili") else {
                throw ContentImportError.unsupportedContent("链接未解析为 B 站单条内容。")
            }
        case .douyin:
            guard extractor.contains("douyin") else {
                throw ContentImportError.unsupportedContent("链接未解析为抖音单条内容。")
            }
        case .fireside, .xiaoyuzhou:
            throw ContentImportError.unsupportedURL
        }
        if payload.isLive == true
            || payload.liveStatus == "is_live"
            || payload.liveStatus == "is_upcoming"
            || payload._type == "playlist"
        {
            throw ContentImportError.unsupportedContent("暂不支持直播或合集内容。")
        }
        let availability = payload.availability?.lowercased() ?? ""
        let requiresRestrictedAccess = [
            "private", "premium", "subscriber", "paid", "login", "auth",
        ].contains { availability.contains($0) }
        guard payload.isPrivate != true, !requiresRestrictedAccess else {
            throw ContentImportError.unsupportedContent("该内容需要登录、订阅或其他受限访问，暂不支持导入。")
        }
    }

    /// A downloaded item may have been changed, redirected, or deleted since it
    /// was first imported. Re-resolve the public URL immediately before the
    /// download and require the same extractor and stable platform content ID.
    private func revalidateDownloadIdentity(
        of content: ImportedAudioMetadata,
        expectedSource: SupportedSource,
        tool: URL
    ) async throws {
        let result = try await runYTDLP(
            executableURL: tool,
            arguments: Self.isolatedYTDLPArguments + [
                "--skip-download",
                "--dump-single-json",
                "--",
                content.sourceURL.absoluteString,
            ],
            workingDirectoryURL: nil,
            source: expectedSource
        )
        try check(result, source: expectedSource)
        let payload = try decodePayload(result.standardOutput)
        try validate(payload: payload, expectedSource: expectedSource)
        guard let id = payload.id, !id.isEmpty, id == content.contentID else {
            throw ContentImportError.mediaUnavailable("这个来源已更新或无法下载，请先重新解析。")
        }
    }

    private func expectedSource(for content: ImportedAudioMetadata) throws -> SupportedSource {
        let sourceFromURL = try SupportedSource.validateSinglePublicItem(url: content.sourceURL)
        let sourceFromPlatform = try source(for: content.platform)
        guard sourceFromURL == sourceFromPlatform else {
            throw ContentImportError.unsupportedContent("链接与已归档内容的平台不一致。")
        }
        return sourceFromPlatform
    }

    private func source(for platform: AudioPlatform) throws -> SupportedSource {
        switch platform {
        case .bilibili: .bilibili
        case .douyin: .douyin
        case .fireside, .fixture, .xiaoyuzhou: throw ContentImportError.unsupportedURL
        }
    }

    private func outputPath(from output: String, below directory: URL) -> URL? {
        let directoryPath = directory.standardizedFileURL.path + "/"
        return
            output
            .split(whereSeparator: \.isNewline)
            .reversed()
            .compactMap { line -> URL? in
                let candidate = URL(
                    fileURLWithPath: String(line).trimmingCharacters(in: .whitespacesAndNewlines)
                ).standardizedFileURL
                guard candidate.path.hasPrefix(directoryPath) else { return nil }
                return candidate
            }
            .first
    }

    private func validatedAudioDuration(of fileURL: URL, ffprobe: URL) async throws -> TimeInterval
    {
        let result = try await runTool(
            executableURL: ffprobe,
            arguments: [
                "-v", "error",
                "-select_streams", "a:0",
                "-show_entries", "stream=codec_type:format=duration",
                "-of", "json",
                fileURL.path,
            ],
            workingDirectoryURL: nil
        )
        guard result.terminationStatus == 0 else {
            throw ContentImportFailure.toolFailure(
                result, tool: "ffprobe", presentation: .invalidDownloadedAudio
            )
        }
        guard let data = result.standardOutput.data(using: .utf8),
            let probe = try? JSONDecoder().decode(FFProbePayload.self, from: data),
            probe.streams.contains(where: { $0.codecType == "audio" }),
            let duration = probe.format?.duration.flatMap(TimeInterval.init),
            duration.isFinite, duration > 0
        else { throw ContentImportError.invalidDownloadedAudio }
        return duration
    }
}

extension SupportedSource {
    fileprivate var displayName: String {
        switch self {
        case .bilibili: "B 站"
        case .douyin: "抖音"
        case .fireside: "Fireside"
        case .xiaoyuzhou: "小宇宙"
        }
    }
}

private struct YTDLPPayload: Decodable {
    let id: String?
    let title: String?
    let uploader: String?
    let channel: String?
    let thumbnail: String?
    let duration: TimeInterval?
    let url: String?
    let httpHeaders: [String: String]?
    let extractor: String?
    let extractorKey: String?
    let isLive: Bool?
    let liveStatus: String?
    let isPrivate: Bool?
    let availability: String?
    let _type: String?

    enum CodingKeys: String, CodingKey {
        case id, title, uploader, channel, thumbnail, duration, url, extractor
        case httpHeaders = "http_headers"
        case extractorKey = "extractor_key"
        case isLive = "is_live"
        case liveStatus = "live_status"
        case isPrivate = "is_private"
        case availability
        case _type
    }
}

private struct FFProbePayload: Decodable {
    struct Stream: Decodable {
        let codecType: String?

        enum CodingKeys: String, CodingKey {
            case codecType = "codec_type"
        }
    }

    struct Format: Decodable {
        let duration: String?
    }

    let streams: [Stream]
    let format: Format?
}

extension String {
    fileprivate var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
