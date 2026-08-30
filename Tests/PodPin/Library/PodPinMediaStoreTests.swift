import Foundation
import XCTest

@testable import PodPinTool

final class PodPinMediaStoreTests: XCTestCase {
    func testRemovingDownloadedAudioPreservesArtworkUntilItemDeletion() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PodPinMediaStoreTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let itemID = UUID()
        let store = try PodPinMediaStore(rootURL: root)
        let directory = store.directory(for: itemID)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let audioURL = directory.appendingPathComponent("audio.m4a")
        let partialURL = directory.appendingPathComponent(".download-partial")
        let artworkURL = directory.appendingPathComponent("artwork")
        try Data("audio".utf8).write(to: audioURL)
        try Data("partial".utf8).write(to: partialURL)
        try Data("artwork".utf8).write(to: artworkURL)

        try await store.removeDownloadedAudio(for: itemID)

        XCTAssertFalse(FileManager.default.fileExists(atPath: audioURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: partialURL.path))
        XCTAssertEqual(try Data(contentsOf: artworkURL), Data("artwork".utf8))

        try await store.removeMedia(for: itemID)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }
}
