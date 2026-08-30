@preconcurrency import AVFoundation
import Foundation
@preconcurrency import MediaPlayer
import XCTest

@testable import OneBox

final class AppCompositionTests: XCTestCase {
    @MainActor
    func testCompositionRegistersExpectedToolsInSidebarOrder() {
        let registrations = AppComposition.makeCatalog().registrations

        XCTAssertEqual(
            registrations.map(\.id.rawValue),
            [
                "ascii-art",
                "stock-watch",
                "podpin",
            ]
        )
    }

    @MainActor
    func testPodPinPlatformAdapterOwnsSystemDefaultDiscovery() {
        let adapter = PodPinSystemPlatformAdapter()

        XCTAssertTrue(adapter.fileManager === FileManager.default)
        XCTAssertTrue(adapter.remoteCommandCenter === MPRemoteCommandCenter.shared())
        XCTAssertTrue(adapter.nowPlayingInfoCenter === MPNowPlayingInfoCenter.default())
        let playerItem = AVPlayerItem(url: URL(fileURLWithPath: "/dev/null"))
        XCTAssertTrue(adapter.makeAudioPlayer(item: playerItem).currentItem === playerItem)
        XCTAssertEqual(adapter.debugFixtureAudioURL?.lastPathComponent, "podpin-sample.m4a")
        XCTAssertEqual(adapter.externalToolsDirectoryURL?.lastPathComponent, "Tools")
    }

    func testToolResourcesAndThirdPartyNoticesAreBundled() throws {
        let asciiBundleURL = try XCTUnwrap(
            Bundle.main.url(
                forResource: "AsciiArtTool_AsciiArtTool",
                withExtension: "bundle"
            )
        )
        let asciiBundle = try XCTUnwrap(Bundle(url: asciiBundleURL))
        XCTAssertNotNil(
            asciiBundle.url(forResource: "onebox-mark-light", withExtension: "png")
        )
        let stockWatchBundleURL = try XCTUnwrap(
            Bundle.main.url(
                forResource: "StockWatchTool_StockWatchTool",
                withExtension: "bundle"
            )
        )
        let stockWatchBundle = try XCTUnwrap(Bundle(url: stockWatchBundleURL))
        XCTAssertNotNil(
            stockWatchBundle.url(forResource: "bull-moo", withExtension: "wav")
        )
        XCTAssertNotNil(
            stockWatchBundle.url(forResource: "bear-growl", withExtension: "wav")
        )
        let fixtureURL = try XCTUnwrap(
            Bundle.main.url(forResource: "podpin-sample", withExtension: "m4a")
        )
        let resourceRoot = try XCTUnwrap(Bundle.main.resourceURL)
        let resourceFiles = try XCTUnwrap(
            FileManager.default.enumerator(
                at: resourceRoot,
                includingPropertiesForKeys: nil
            )?.allObjects as? [URL]
        )
        XCTAssertEqual(
            resourceFiles.filter { $0.lastPathComponent == fixtureURL.lastPathComponent }.count,
            1
        )
        XCTAssertNotNil(Bundle.main.url(forResource: "GRDB-MIT", withExtension: "txt"))
        XCTAssertNotNil(
            Bundle.main.url(forResource: "THIRD_PARTY_NOTICES", withExtension: "md")
        )
    }
}
