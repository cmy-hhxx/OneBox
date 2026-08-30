import Foundation
import XCTest

@testable import PodPinTool

final class MediaMaterializerTests: XCTestCase {
    func testMaterializerDownloadsRemuxesValidatesAndAtomicallyPublishesM4A() async throws {
        let destination = FileManager.default.temporaryDirectory
            .appending(
                path: "MediaMaterializerTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: destination) }
        let sourceURL = URL(string: "https://media.xyzcdn.net/public/source.m4a")!
        let transport = MaterializerHTTPTransport(sourceURL: sourceURL)
        let runner = MaterializerToolRunner()
        let materializer = MediaMaterializer(
            transport: transport,
            runner: runner,
            toolLocator: BundledToolLocator(overrides: [
                "ffmpeg": try makeTestExecutable(named: "ffmpeg"),
                "ffprobe": try makeTestExecutable(named: "ffprobe"),
            ])
        )

        let result = try await materializer.materialize(
            stream: ResolvedAudioStream(
                url: sourceURL,
                headers: ["Referer": "https://www.xiaoyuzhoufm.com/"],
                duration: 42
            ),
            to: destination,
            progress: { _ in }
        )

        XCTAssertEqual(result.url, destination.appending(path: "audio.m4a"))
        XCTAssertEqual(result.duration, 42.5)
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.url.path))
        let calls = await runner.calls
        XCTAssertEqual(calls.map(\.executable), ["ffmpeg", "ffprobe"])
        XCTAssertTrue(calls[0].arguments.contains("copy"))
        XCTAssertFalse(calls[0].arguments.contains("aac"))
    }

    func testMaterializerAcceptsFiresideMediaRedirect() async throws {
        let destination = FileManager.default.temporaryDirectory
            .appending(
                path: "MediaMaterializerTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: destination) }
        let sourceURL = URL(string: "https://aphid.fireside.fm/d/episode.mp3")!
        let redirectedURL = URL(
            string: "https://media24.fireside.fm/file/fireside-audio/episode.mp3")!
        let materializer = MediaMaterializer(
            transport: MaterializerHTTPTransport(
                sourceURL: sourceURL,
                responseURL: redirectedURL
            ),
            runner: MaterializerToolRunner(),
            toolLocator: BundledToolLocator(overrides: [
                "ffmpeg": try makeTestExecutable(named: "ffmpeg"),
                "ffprobe": try makeTestExecutable(named: "ffprobe"),
            ])
        )

        let result = try await materializer.materialize(
            stream: ResolvedAudioStream(url: sourceURL, headers: [:], duration: 42),
            to: destination,
            progress: { _ in }
        )

        XCTAssertEqual(result.url, destination.appending(path: "audio.m4a"))
    }

    func testMaterializerTranscodesWhenStreamCopyCannotProduceM4A() async throws {
        let destination = FileManager.default.temporaryDirectory
            .appending(
                path: "MediaMaterializerTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: destination) }
        let sourceURL = URL(string: "https://media24.fireside.fm/file/fireside-audio/episode.mp3")!
        let runner = MaterializerToolRunner(failsStreamCopy: true)
        let materializer = MediaMaterializer(
            transport: MaterializerHTTPTransport(sourceURL: sourceURL),
            runner: runner,
            toolLocator: BundledToolLocator(overrides: [
                "ffmpeg": try makeTestExecutable(named: "ffmpeg"),
                "ffprobe": try makeTestExecutable(named: "ffprobe"),
            ])
        )

        let result = try await materializer.materialize(
            stream: ResolvedAudioStream(url: sourceURL, headers: [:], duration: 42),
            to: destination,
            progress: { _ in }
        )

        XCTAssertEqual(result.url, destination.appending(path: "audio.m4a"))
        let calls = await runner.calls
        XCTAssertEqual(calls.map(\.executable), ["ffmpeg", "ffmpeg", "ffprobe"])
        XCTAssertTrue(calls[0].arguments.contains("copy"))
        XCTAssertTrue(calls[1].arguments.contains("aac"))
    }
}

private struct MaterializerHTTPTransport: HTTPTransporting {
    let sourceURL: URL
    var responseURL: URL? = nil

    func data(for request: URLRequest) async throws -> HTTPTransportResponse {
        let response = HTTPURLResponse(
            url: responseURL ?? sourceURL,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!
        return HTTPTransportResponse(data: Data([1, 2, 3]), response: response)
    }
}

private actor MaterializerToolRunner: ExternalToolRunning {
    struct Call: Sendable {
        let executable: String
        let arguments: [String]
    }

    private(set) var calls: [Call] = []
    private let failsStreamCopy: Bool

    init(failsStreamCopy: Bool = false) {
        self.failsStreamCopy = failsStreamCopy
    }

    func run(
        executableURL: URL,
        arguments: [String],
        workingDirectoryURL: URL?
    ) async throws -> ExternalToolResult {
        calls.append(Call(executable: executableURL.lastPathComponent, arguments: arguments))
        if executableURL.lastPathComponent == "ffmpeg" {
            if failsStreamCopy, arguments.contains("copy") {
                return ExternalToolResult(
                    standardOutput: "",
                    standardError: "codec is not supported in container",
                    terminationStatus: 1
                )
            }
            guard let outputPath = arguments.last else {
                throw ContentImportError.invalidDownloadedAudio
            }
            let output = URL(fileURLWithPath: outputPath)
            try Data([4, 5, 6]).write(to: output, options: .atomic)
            return ExternalToolResult(standardOutput: "", standardError: "", terminationStatus: 0)
        }
        return ExternalToolResult(
            standardOutput: #"{"streams":[{"codec_type":"audio"}],"format":{"duration":"42.5"}}"#,
            standardError: "",
            terminationStatus: 0
        )
    }
}
