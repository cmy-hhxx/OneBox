import Foundation
import Testing

@testable import AsciiArtTool

@MainActor
@Suite("ASCII session lifecycle")
struct AsciiSessionTests {
    @Test
    func `animation pauses offscreen and resumes with the in-memory session`() {
        let session = AsciiSession()

        session.setVisible(true)
        #expect(session.isAnimationActive)

        session.setVisible(false)
        #expect(!session.isAnimationActive)

        session.setVisible(true)
        #expect(session.isAnimationActive)
        #expect(session.settings.animation == .wave)
    }

    @Test
    func `reduce motion defaults static but manual play explicitly starts animation`() {
        let session = AsciiSession()
        session.setVisible(true)

        session.setReduceMotion(true)
        #expect(!session.isAnimationActive)

        session.togglePlayback()
        #expect(session.isAnimationActive)
    }

    @Test
    func `metal readiness presents and clears the typed failure`() {
        let session = AsciiSession()

        session.setMetalReady(false)
        #expect(session.statusError == .metalUnavailable)

        session.setMetalReady(true)
        #expect(session.statusError == nil)
    }

    @Test
    func `metal failure remains visible over a transient operation error`() {
        let session = AsciiSession()

        session.setMetalReady(false)
        session.report(.decodeFailed)
        #expect(session.statusError == .metalUnavailable)

        session.setMetalReady(true)
        #expect(session.statusError == .decodeFailed)
    }

    @Test
    func `parameters start visible and keep the user's collapsed state`() {
        let session = AsciiSession()

        #expect(session.isInspectorPresented)

        session.isInspectorPresented = false
        #expect(!session.isInspectorPresented)
    }

    @Test
    func `failed import keeps the last valid source`() async throws {
        let session = AsciiSession()
        session.prepareInitialSource()
        let originalName = session.source?.name
        let url = try temporaryFile(name: "broken.png", data: Data("broken".utf8))
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        session.importImage(from: url)
        await waitForImport(session)

        #expect(session.source?.name == originalName)
        #expect(session.statusMessage == AsciiToolError.decodeFailed.actionMessage)
    }

    @Test
    func `rapid imports apply only the latest result`() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = directory.appending(path: "first.svg")
        let second = directory.appending(path: "second.svg")
        try Data(svg(width: 200).utf8).write(to: first)
        try Data(svg(width: 80).utf8).write(to: second)
        let session = AsciiSession()

        session.importImage(from: first)
        session.importImage(from: second)
        await waitForImport(session)

        #expect(session.source?.name == "second.svg")
    }

    private func temporaryFile(name: String, data: Data) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: name)
        try data.write(to: url)
        return url
    }

    private func svg(width: Int) -> String {
        """
        <svg xmlns="http://www.w3.org/2000/svg" width="\(width)" height="40">
          <rect width="100%" height="100%" fill="#000000"/>
        </svg>
        """
    }

    private func waitForImport(_ session: AsciiSession) async {
        for _ in 0..<200 where session.isImporting {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }
}
