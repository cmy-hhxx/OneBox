import Foundation
import XCTest

@testable import PodPinTool

final class FixtureContentImporterTests: XCTestCase {
    func testBundledFixtureCanBeProbedResolvedAndSavedOffline() async throws {
        let importer = try FixtureContentImporter.testFixture()
        let discovery = try await importer.probe(url: FixtureContentImporter.sampleURL)
        let metadata = discovery.primaryItem
        let stream = try await importer.resolveStream(for: metadata)

        XCTAssertEqual(discovery.items, [metadata])
        XCTAssertNil(discovery.groupTitle)
        XCTAssertEqual(metadata.platform, .fixture)
        XCTAssertEqual(metadata.contentID, "welcome")
        XCTAssertTrue(FileManager.default.fileExists(atPath: stream.url.path))

        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("PodPinFixtureTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: destination) }

        let downloaded = try await importer.download(
            content: metadata,
            to: destination,
            progress: { _ in }
        )
        XCTAssertEqual(downloaded.url.lastPathComponent, "audio.m4a")
        XCTAssertTrue(FileManager.default.fileExists(atPath: downloaded.url.path))
        XCTAssertEqual(downloaded.duration, 8)
    }

    func testBundledFixtureProvidesDeterministicCollectionSegments() async throws {
        let importer = try FixtureContentImporter.testFixture()
        let discovery = try await importer.probe(url: FixtureContentImporter.collectionSampleURL)

        XCTAssertEqual(discovery.groupTitle, "PodPin 示例合集")
        XCTAssertEqual(
            discovery.items.map(\.contentID),
            ["collection-part-1", "collection-part-2", "collection-part-3"]
        )
        XCTAssertEqual(
            discovery.items.map(\.title),
            ["PodPin 示例分段 1", "PodPin 示例分段 2", "PodPin 示例分段 3"]
        )
    }
}
