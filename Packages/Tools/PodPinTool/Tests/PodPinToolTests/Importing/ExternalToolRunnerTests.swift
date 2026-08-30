import Darwin
import Foundation
import XCTest

@testable import PodPinTool

final class ExternalToolRunnerTests: XCTestCase {
    func testDrainsLargeStandardOutputAndErrorBeforeProcessExit() async throws {
        let runner = ProcessToolRunner()
        let byteCount = 131_072
        let result = try await runner.run(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: [
                "-c",
                "yes x | head -c \(byteCount); yes e | head -c \(byteCount) >&2",
            ],
            workingDirectoryURL: nil
        )

        XCTAssertEqual(result.terminationStatus, 0)
        XCTAssertEqual(result.standardOutput.utf8.count, byteCount)
        XCTAssertEqual(result.standardError.utf8.count, byteCount)
    }

    func testTimeoutTerminatesRunningProcessGroup() async throws {
        let runner = ProcessToolRunner(timeout: .milliseconds(250))
        let processIDFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("PodPin-timeout-pid-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: processIDFile) }

        let task = Task.detached {
            try await runner.run(
                executableURL: URL(fileURLWithPath: "/bin/sh"),
                arguments: [
                    "-c",
                    "printf '%s\\n' \"$$\" > \"$1\"; sleep 30",
                    "podpin-process-timeout-test",
                    processIDFile.path,
                ],
                workingDirectoryURL: nil
            )
        }

        let processID = try await waitForChildPID(at: processIDFile)
        do {
            _ = try await task.value
            XCTFail("expected timeout")
        } catch let error as ExternalToolRunnerError {
            XCTAssertEqual(error, .timedOut)
        }
        try await waitForProcessToExit(processID)
    }

    func testCancellingRunningProcessReturnsCancellationPromptly() async throws {
        let runner = ProcessToolRunner()
        let childPIDFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("PodPin-child-pid-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: childPIDFile) }
        // Keep cancellation delivery independent from XCTest's app-host actor
        // and its run loop. The runner itself is Sendable by contract.
        let task = Task.detached {
            try await runner.run(
                executableURL: URL(fileURLWithPath: "/bin/sh"),
                arguments: [
                    "-c",
                    "sleep 30 & child=$!; printf '%s\\n' \"$child\" > \"$1\"; wait \"$child\"",
                    "podpin-process-tree-test",
                    childPIDFile.path,
                ],
                workingDirectoryURL: nil
            )
        }

        let childPID = try await waitForChildPID(at: childPIDFile)
        defer {
            if isRunning(processID: childPID) {
                _ = kill(childPID, SIGKILL)
            }
        }
        XCTAssertTrue(isRunning(processID: childPID))
        let cancelledAt = Date()
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("expected cancellation")
        } catch is CancellationError {
            XCTAssertLessThan(Date().timeIntervalSince(cancelledAt), 2)
        }
        try await waitForProcessToExit(childPID)
    }

    func testToolLocatorUsesOnlyInjectedExecutableFiles() throws {
        let ffmpegURL = try makeTestExecutable(named: "ffmpeg")
        let directoryURL = ffmpegURL.deletingLastPathComponent()
        let ffprobeURL = directoryURL.appending(path: "ffprobe")
        try "not executable".write(
            to: ffprobeURL,
            atomically: true,
            encoding: .utf8
        )
        let locator = BundledToolLocator(toolsDirectoryURL: directoryURL)

        XCTAssertEqual(try locator.executableURL(named: "ffmpeg"), ffmpegURL)
        XCTAssertThrowsError(try locator.executableURL(named: "ffprobe"))
        XCTAssertThrowsError(try locator.executableURL(named: "yt-dlp"))
        XCTAssertThrowsError(
            try BundledToolLocator(overrides: ["yt-dlp": ffprobeURL])
                .executableURL(named: "yt-dlp")
        )
    }

    private func waitForChildPID(
        at fileURL: URL,
        timeout: TimeInterval = 2
    ) async throws -> pid_t {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let contents = try? String(contentsOf: fileURL, encoding: .utf8),
                let processID = pid_t(contents.trimmingCharacters(in: .whitespacesAndNewlines)),
                processID > 0
            {
                return processID
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw TestFailure.timeout("child PID was not written")
    }

    private func waitForProcessToExit(
        _ processID: pid_t,
        timeout: TimeInterval = 2
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while isRunning(processID: processID) {
            guard Date() < deadline else {
                throw TestFailure.timeout("child process \(processID) survived cancellation")
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    private func isRunning(processID: pid_t) -> Bool {
        if kill(processID, 0) == 0 { return true }
        return errno == EPERM
    }
}

private enum TestFailure: LocalizedError {
    case timeout(String)

    var errorDescription: String? {
        switch self {
        case .timeout(let message): message
        }
    }
}
