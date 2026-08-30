import Foundation

protocol MediaMaterializing: Sendable {
    func materialize(
        stream: ResolvedAudioStream,
        to destinationDirectory: URL,
        progress: @escaping @Sendable (DownloadProgressSnapshot) -> Void
    ) async throws -> DownloadedAudioFile
}

actor MediaMaterializer: MediaMaterializing {
    private let transport: any HTTPTransporting
    private let runner: any ExternalToolRunning
    private let toolLocator: BundledToolLocator
    private let fileManager: FileManager

    init(
        transport: any HTTPTransporting = URLSessionHTTPTransport(),
        runner: any ExternalToolRunning = ProcessToolRunner(),
        toolLocator: BundledToolLocator = BundledToolLocator(),
        fileManager: FileManager = .default
    ) {
        self.transport = transport
        self.runner = runner
        self.toolLocator = toolLocator
        self.fileManager = fileManager
    }

    func materialize(
        stream: ResolvedAudioStream,
        to destinationDirectory: URL,
        progress: @escaping @Sendable (DownloadProgressSnapshot) -> Void
    ) async throws -> DownloadedAudioFile {
        try Task.checkCancellation()
        let ffmpeg = try toolLocator.executableURL(named: "ffmpeg")
        let ffprobe = try toolLocator.executableURL(named: "ffprobe")
        let temporaryDirectory =
            destinationDirectory
            .appendingPathComponent(".download-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: temporaryDirectory) }

        var request = URLRequest(url: stream.url)
        request.timeoutInterval = 120
        for (name, value) in stream.headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        let response = try await transport.download(for: request) { downloadProgress in
            progress(downloadProgress.scaled(to: 0.9))
        }
        defer { try? fileManager.removeItem(at: response.temporaryURL) }
        guard (200..<300).contains(response.response.statusCode),
            let resolvedURL = response.response.url,
            Self.acceptsRedirect(from: stream.url, to: resolvedURL),
            (try? response.temporaryURL.resourceValues(forKeys: [.fileSizeKey]).fileSize).map({
                $0 > 0
            }) == true
        else { throw ContentImportError.mediaUnavailable("音频地址已经失效，请重新尝试。") }

        progress(DownloadProgressSnapshot(fraction: 0.9, bytesPerSecond: nil))
        try Task.checkCancellation()

        let converted = temporaryDirectory.appendingPathComponent("audio.m4a")
        let remux = try await run(
            executableURL: ffmpeg,
            arguments: [
                "-hide_banner", "-loglevel", "error", "-y",
                "-i", response.temporaryURL.path,
                "-vn", "-c:a", "copy",
                converted.path,
            ]
        )
        if remux.terminationStatus != 0 || !fileManager.fileExists(atPath: converted.path) {
            try? fileManager.removeItem(at: converted)
            let transcode = try await run(
                executableURL: ffmpeg,
                arguments: [
                    "-hide_banner", "-loglevel", "error", "-y",
                    "-i", response.temporaryURL.path,
                    "-vn", "-c:a", "aac", "-b:a", "128k",
                    converted.path,
                ]
            )
            guard transcode.terminationStatus == 0,
                fileManager.fileExists(atPath: converted.path)
            else { throw ContentImportError.invalidDownloadedAudio }
        }
        guard fileManager.fileExists(atPath: converted.path) else {
            throw ContentImportError.invalidDownloadedAudio
        }

        let duration = try await validatedDuration(of: converted, ffprobe: ffprobe)
        try Task.checkCancellation()
        try fileManager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        let finalURL = destinationDirectory.appendingPathComponent("audio.m4a")
        if fileManager.fileExists(atPath: finalURL.path) {
            try fileManager.removeItem(at: finalURL)
        }
        try fileManager.moveItem(at: converted, to: finalURL)
        progress(.complete)
        return DownloadedAudioFile(url: finalURL, duration: duration)
    }

    private func validatedDuration(of fileURL: URL, ffprobe: URL) async throws -> TimeInterval {
        let result = try await run(
            executableURL: ffprobe,
            arguments: [
                "-v", "error",
                "-select_streams", "a:0",
                "-show_entries", "stream=codec_type:format=duration",
                "-of", "json",
                fileURL.path,
            ]
        )
        guard result.terminationStatus == 0,
            let data = result.standardOutput.data(using: .utf8),
            let payload = try? JSONDecoder().decode(MediaProbePayload.self, from: data),
            payload.streams.contains(where: { $0.codecType == "audio" }),
            let durationString = payload.format?.duration,
            let duration = TimeInterval(durationString),
            duration.isFinite, duration > 0
        else { throw ContentImportError.invalidDownloadedAudio }
        return duration
    }

    private func run(executableURL: URL, arguments: [String]) async throws -> ExternalToolResult {
        do {
            return try await runner.run(
                executableURL: executableURL,
                arguments: arguments,
                workingDirectoryURL: nil
            )
        } catch is CancellationError {
            throw ContentImportError.cancelled
        }
    }

    private static func acceptsRedirect(from original: URL, to final: URL) -> Bool {
        guard original.scheme == "https", final.scheme == "https",
            let originalHost = original.host?.lowercased(),
            let finalHost = final.host?.lowercased()
        else { return false }
        if originalHost == finalHost { return true }
        let approvedFamilies = [
            "xyzcdn.net",
            "bilivideo.com",
            "bilivideo.cn",
            "douyinvod.com",
            "bytecdn.cn",
            "fireside.fm",
        ]
        return approvedFamilies.contains { family in
            (originalHost == family || originalHost.hasSuffix(".\(family)"))
                && (finalHost == family || finalHost.hasSuffix(".\(family)"))
        }
    }
}

private struct MediaProbePayload: Decodable {
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
