import Foundation
import XCTest

@testable import PodPinTool

final class YTDLPContentImporterTests: XCTestCase {
    func testProbePassesURLAsASeparateArgumentAndRejectsPlaylistOutput() async throws {
        let runner = RecordingRunner(
            result: .init(
                standardOutput: """
                    {"id":"abc","title":"A collection","extractor_key":"BiliBili","_type":"playlist"}
                    """,
                standardError: "",
                terminationStatus: 0
            ))
        let executable = try makeTestExecutable(named: "yt-dlp")
        let importer = YTDLPContentImporter(
            runner: runner,
            toolLocator: BundledToolLocator(overrides: ["yt-dlp": executable])
        )
        let sourceURL = URL(string: "https://www.bilibili.com/video/BV1xx411c7mD?x=one;two")!

        do {
            _ = try await importer.probe(url: sourceURL)
            XCTFail("playlist should be rejected")
        } catch ContentImportError.unsupportedContent {
            // Expected.
        }

        let calls = await runner.calls
        let call = try XCTUnwrap(calls.first)
        XCTAssertEqual(call.executableURL, executable)
        XCTAssertEqual(
            Array(call.arguments.prefix(4)),
            ["--ignore-config", "--no-plugin-dirs", "--no-playlist", "--no-warnings"]
        )
        XCTAssertEqual(call.arguments.suffix(2), ["--", sourceURL.absoluteString])
        XCTAssertFalse(call.arguments.contains(where: { $0.contains("sh -c") }))
    }

    func testProbeRejectsMismatchedExtractor() async throws {
        let runner = RecordingRunner(
            result: .init(
                standardOutput: """
                    {"id":"abc","title":"Wrong site","extractor_key":"Douyin"}
                    """,
                standardError: "",
                terminationStatus: 0
            ))
        let importer = YTDLPContentImporter(
            runner: runner,
            toolLocator: BundledToolLocator(overrides: [
                "yt-dlp": try makeTestExecutable(named: "yt-dlp")
            ])
        )

        await assertThrowsErrorAsync {
            _ = try await importer.probe(
                url: URL(string: "https://www.bilibili.com/video/BV1xx411c7mD")!
            )
        }
    }

    func testProbeRejectsPrivateOrPaidAvailability() async throws {
        let runner = RecordingRunner(
            result: .init(
                standardOutput: """
                    {"id":"abc","title":"Restricted","extractor_key":"BiliBili","availability":"needs_auth"}
                    """,
                standardError: "",
                terminationStatus: 0
            ))
        let importer = YTDLPContentImporter(
            runner: runner,
            toolLocator: BundledToolLocator(overrides: [
                "yt-dlp": try makeTestExecutable(named: "yt-dlp")
            ])
        )

        do {
            _ = try await importer.probe(
                url: URL(string: "https://www.bilibili.com/video/BV1xx411c7mD")!
            )
            XCTFail("restricted content should be rejected")
        } catch ContentImportError.unsupportedContent {
            // Expected.
        }
    }

    func testCancellationBecomesAUserFacingImportCancellation() async throws {
        let importer = YTDLPContentImporter(
            runner: CancelledRunner(),
            toolLocator: BundledToolLocator(overrides: [
                "yt-dlp": try makeTestExecutable(named: "yt-dlp")
            ])
        )

        do {
            _ = try await importer.probe(
                url: URL(string: "https://www.bilibili.com/video/BV1xx411c7mD")!
            )
            XCTFail("expected cancellation")
        } catch let error as ContentImportError {
            XCTAssertEqual(error, .cancelled)
        }
    }

    func testDownloadRevalidatesContentIDBeforeStartingDownload() async throws {
        let runner = RecordingRunner(
            result: .init(
                standardOutput: """
                    {"id":"replaced","title":"Replacement","extractor_key":"BiliBili"}
                    """,
                standardError: "",
                terminationStatus: 0
            ))
        let sourceURL = URL(string: "https://www.bilibili.com/video/BV1xx411c7mD")!
        let importer = YTDLPContentImporter(
            runner: runner,
            toolLocator: BundledToolLocator(overrides: [
                "yt-dlp": try makeTestExecutable(named: "yt-dlp")
            ])
        )

        do {
            _ = try await importer.download(
                content: ImportedAudioMetadata(
                    platform: .bilibili,
                    contentID: "abc",
                    sourceURL: sourceURL,
                    title: "Original",
                    author: nil,
                    artworkURL: nil,
                    duration: nil
                ),
                to: URL(fileURLWithPath: "/tmp/PodPinTests"),
                progress: { _ in }
            )
            XCTFail("a changed content ID should be rejected")
        } catch ContentImportError.mediaUnavailable {
            // Expected.
        }

        let calls = await runner.calls
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(
            Array(calls[0].arguments.prefix(4)),
            ["--ignore-config", "--no-plugin-dirs", "--no-playlist", "--no-warnings"]
        )
        XCTAssertEqual(calls[0].arguments.suffix(2), ["--", sourceURL.absoluteString])
    }

    func testDownloadRejectsAResolvedPlatformMismatchBeforeStartingDownload() async throws {
        let runner = RecordingRunner(
            result: .init(
                standardOutput: """
                    {"id":"abc","title":"Wrong site","extractor_key":"Douyin"}
                    """,
                standardError: "",
                terminationStatus: 0
            ))
        let importer = YTDLPContentImporter(
            runner: runner,
            toolLocator: BundledToolLocator(overrides: [
                "yt-dlp": try makeTestExecutable(named: "yt-dlp")
            ])
        )

        do {
            _ = try await importer.download(
                content: ImportedAudioMetadata(
                    platform: .bilibili,
                    contentID: "abc",
                    sourceURL: URL(string: "https://www.bilibili.com/video/BV1xx411c7mD")!,
                    title: "Original",
                    author: nil,
                    artworkURL: nil,
                    duration: nil
                ),
                to: URL(fileURLWithPath: "/tmp/PodPinTests"),
                progress: { _ in }
            )
            XCTFail("a platform mismatch should be rejected")
        } catch ContentImportError.unsupportedContent {
            // Expected.
        }

        let calls = await runner.calls
        XCTAssertEqual(calls.count, 1)
    }

    func testFreshCookieStderrIsNotMisreportedAsBrowserAuthentication() async throws {
        let runner = RecordingRunner(
            result: .init(
                standardOutput: "",
                standardError: "Fresh cookies (not necessarily logged in) are needed",
                terminationStatus: 1
            ))
        let sourceURL = URL(string: "https://v.douyin.com/Ne1f5EXZW4Q/")!
        let importer = YTDLPContentImporter(
            runner: runner,
            toolLocator: BundledToolLocator(overrides: [
                "yt-dlp": try makeTestExecutable(named: "yt-dlp")
            ])
        )

        do {
            _ = try await importer.probe(url: sourceURL)
            XCTFail("the failed extractor should remain a platform failure")
        } catch ContentImportError.platformUnavailable {
            // Expected: stderr text is not an authentication signal.
        }
    }

    func testTemporaryCookieFileIsPassedThenRemovedAfterInvocation() async throws {
        let cookieURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("podpin-test-cookie-\(UUID().uuidString).txt")
        try "# Netscape HTTP Cookie File\n".write(to: cookieURL, atomically: true, encoding: .utf8)
        let runner = RecordingRunner(
            result: .init(
                standardOutput: """
                    {"id":"abc","title":"Public item","extractor_key":"Douyin"}
                    """,
                standardError: "",
                terminationStatus: 0
            ))
        let importer = YTDLPContentImporter(
            runner: runner,
            toolLocator: BundledToolLocator(overrides: [
                "yt-dlp": try makeTestExecutable(named: "yt-dlp")
            ]),
            anonymousSession: CookieFileSession(cookieURL: cookieURL)
        )

        _ = try await importer.probe(url: URL(string: "https://v.douyin.com/Ne1f5EXZW4Q/")!)

        let calls = await runner.calls
        let call = try XCTUnwrap(calls.first)
        XCTAssertEqual(
            Array(call.arguments.prefix(6)),
            [
                "--ignore-config", "--no-plugin-dirs", "--no-playlist", "--no-warnings",
                "--cookies", cookieURL.path,
            ]
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: cookieURL.path))
    }
}

private actor RecordingRunner: ExternalToolRunning {
    struct Call: Sendable, Equatable {
        let executableURL: URL
        let arguments: [String]
    }

    let result: ExternalToolResult
    private(set) var calls: [Call] = []

    init(result: ExternalToolResult) {
        self.result = result
    }

    func run(
        executableURL: URL,
        arguments: [String],
        workingDirectoryURL: URL?
    ) async throws -> ExternalToolResult {
        calls.append(Call(executableURL: executableURL, arguments: arguments))
        return result
    }
}

private struct CancelledRunner: ExternalToolRunning {
    func run(
        executableURL: URL,
        arguments: [String],
        workingDirectoryURL: URL?
    ) async throws -> ExternalToolResult {
        throw CancellationError()
    }
}

private actor CookieFileSession: AnonymousSessionProviding {
    private let cookieURL: URL

    init(cookieURL: URL) {
        self.cookieURL = cookieURL
    }

    func cookieFile(for source: SupportedSource) async throws -> URL? {
        cookieURL
    }

    func hasVerificationCookie(for source: SupportedSource) async -> Bool {
        true
    }

    func discard() async {}
}

private func assertThrowsErrorAsync(
    _ expression: @escaping () async throws -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        try await expression()
        XCTFail("expected error", file: file, line: line)
    } catch {
        // Expected.
    }
}
