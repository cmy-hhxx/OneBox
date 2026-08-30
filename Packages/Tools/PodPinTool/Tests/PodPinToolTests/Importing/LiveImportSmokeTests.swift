import AVFoundation
import Foundation
import XCTest

@testable import PodPinTool

/// Opt-in platform contract tests. Default CI skips them because the source
/// websites and network are intentionally outside the deterministic suite.
final class LiveImportSmokeTests: XCTestCase {
    private let samples: [(SupportedSource, URL)] = [
        (.bilibili, URL(string: "https://www.bilibili.com/video/BV1MN4dewEQZ/")!),
        (.douyin, URL(string: "https://v.douyin.com/Ne1f5EXZW4Q/")!),
        (.fireside, URL(string: "https://sv101.fireside.fm/260")!),
        (
            .xiaoyuzhou,
            URL(string: "https://www.xiaoyuzhoufm.com/episode/6a75424b000a55a9bb042560")!
        ),
    ]

    override func setUpWithError() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["PODPIN_RUN_LIVE_IMPORTS"] == "YES",
            "Run ./scripts/test.sh --podpin-live for live platform contract checks."
        )
    }

    func testBilibiliSampleDiscoversTwentySixPartsAndReadsMedia() async throws {
        let result = try await resolve(.bilibili)
        XCTAssertEqual(result.discovery.items.count, 26)
        try await assertReadable(result.stream)
    }

    func testDouyinSampleHasExpectedIdentityAndReadableAudio() async throws {
        let result = try await resolve(.douyin)
        XCTAssertEqual(result.discovery.primaryItem.contentID, "7667887133545205043")
        try await assertReadable(result.stream)
    }

    func testDouyinUserReportedSampleDoesNotRequestBrowserAccess() async throws {
        let url = URL(string: "https://v.douyin.com/25Kk0YvJFw0/")!
        do {
            let page = try await DouyinWebPageLoader().load(url: url, cookies: [])
            XCTAssertEqual(page.canonicalURL.pathComponents.last, "7647161944600644977")
            XCTAssertFalse(page.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            XCTAssertEqual(page.audioURL.scheme, "https")
            var headers = [
                "Referer": page.canonicalURL.absoluteString,
                "User-Agent": page.userAgent,
            ]
            if !page.cookies.isEmpty {
                headers["Cookie"] = page.cookies
                    .map { "\($0.name)=\($0.value)" }
                    .joined(separator: "; ")
            }
            try await assertReadable(
                ResolvedAudioStream(
                    url: page.audioURL,
                    headers: headers,
                    duration: page.duration,
                    mimeType: "audio/mp4"
                ))
        } catch let DouyinPageLoadError.challenge(reasons) {
            XCTFail(
                "A public Douyin sample hit challenge detection: \(reasons.joined(separator: ", "))"
            )
        } catch let DouyinPageLoadError.restricted(reasons) {
            XCTFail(
                "A public Douyin sample hit restriction detection: \(reasons.joined(separator: ", "))"
            )
        } catch let DouyinPageLoadError.ambiguousAudio(diagnostic) {
            XCTFail("A public Douyin sample returned ambiguous audio: \(diagnostic)")
        } catch let DouyinPageLoadError.timeout(diagnostic) {
            XCTFail("A public Douyin sample timed out: \(diagnostic)")
        } catch {
            let cocoaError = error as NSError
            XCTFail(
                "Douyin runtime failed: type=\(type(of: error)), "
                    + "domain=\(cocoaError.domain), code=\(cocoaError.code), "
                    + "description=\(cocoaError.localizedDescription)"
            )
        }
    }

    func testXiaoyuzhouSampleHasStableEpisodeMetadataAndReadsMedia() async throws {
        let result = try await resolve(.xiaoyuzhou)
        XCTAssertEqual(result.discovery.primaryItem.contentID, "6a75424b000a55a9bb042560")
        XCTAssertEqual(result.discovery.primaryItem.author, "42章经")
        XCTAssertEqual(result.discovery.primaryItem.duration ?? 0, 3569, accuracy: 1)
        try await assertReadable(result.stream)
    }

    func testFiresideSampleHasPodcastScopedIdentityAndReadsMedia() async throws {
        let result = try await resolve(.fireside)
        XCTAssertEqual(result.discovery.primaryItem.contentID, "sv101.fireside.fm/260")
        XCTAssertEqual(result.discovery.primaryItem.author, "硅谷101")
        XCTAssertEqual(result.discovery.primaryItem.duration ?? 0, 6_386, accuracy: 1)
        try await assertReadable(result.stream)
    }

    func testBilibiliSampleDownloadsCompleteM4A() async throws {
        try requireLiveDownloads()
        try await assertCompleteDownload(.bilibili)
    }

    func testXiaoyuzhouSampleDownloadsCompleteM4A() async throws {
        try requireLiveDownloads()
        try await assertCompleteDownload(.xiaoyuzhou)
    }

    func testFiresideSampleDownloadsCompleteM4A() async throws {
        try requireLiveDownloads()
        try await assertCompleteDownload(.fireside)
    }

    private func resolve(
        _ source: SupportedSource
    ) async throws -> (discovery: ImportDiscovery, stream: ResolvedAudioStream) {
        let importer = PodPinContentImporter()
        let url = try XCTUnwrap(samples.first(where: { $0.0 == source })?.1)
        let discovery = try await importer.probe(url: url)
        let stream = try await importer.resolveStream(for: discovery.primaryItem)
        return (discovery, stream)
    }

    private func assertReadable(_ stream: ResolvedAudioStream) async throws {
        var options: [String: Any] = ["AVURLAssetHTTPHeaderFieldsKey": stream.headers]
        options[AVURLAssetOverrideMIMETypeKey] = stream.mimeType
        let asset = AVURLAsset(url: stream.url, options: options)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        XCTAssertFalse(tracks.isEmpty)
    }

    private func requireLiveDownloads() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["PODPIN_RUN_LIVE_DOWNLOADS"] == "YES",
            "Run ./scripts/test.sh --podpin-live-downloads for complete media downloads."
        )
    }

    private func assertCompleteDownload(_ source: SupportedSource) async throws {
        let environment = ProcessInfo.processInfo.environment
        let ffmpegPath = try XCTUnwrap(environment["PODPIN_FFMPEG_PATH"])
        let ffprobePath = try XCTUnwrap(environment["PODPIN_FFPROBE_PATH"])
        let importer = PodPinContentImporter(
            mediaMaterializer: MediaMaterializer(
                toolLocator: BundledToolLocator(overrides: [
                    "ffmpeg": URL(fileURLWithPath: ffmpegPath),
                    "ffprobe": URL(fileURLWithPath: ffprobePath),
                ])
            ))
        let url = try XCTUnwrap(samples.first(where: { $0.0 == source })?.1)
        let discovery = try await importer.probe(url: url)
        let destination = FileManager.default.temporaryDirectory
            .appending(path: "PodPinLiveDownload-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: destination) }

        let progress = LiveDownloadProgressRecorder()
        let downloaded = try await importer.download(
            content: discovery.primaryItem,
            to: destination,
            progress: progress.record
        )

        XCTAssertEqual(downloaded.url.lastPathComponent, "audio.m4a")
        XCTAssertGreaterThan(downloaded.duration, 0)
        let byteCount = try downloaded.url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        XCTAssertGreaterThan(byteCount, 0)
        let tracks = try await AVURLAsset(url: downloaded.url).loadTracks(withMediaType: .audio)
        XCTAssertFalse(tracks.isEmpty)
        if source == .fireside {
            XCTAssertTrue(
                progress.values.contains { value in
                    guard let value = value.fraction else { return false }
                    return value > 0 && value < 0.9
                })
        }
    }
}

private final class LiveDownloadProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedValues: [DownloadProgressSnapshot] = []

    var values: [DownloadProgressSnapshot] {
        lock.withLock { recordedValues }
    }

    func record(_ value: DownloadProgressSnapshot) {
        lock.withLock {
            recordedValues.append(value)
        }
    }
}
