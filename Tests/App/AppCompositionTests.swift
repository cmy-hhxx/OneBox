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
    }

    func testToolResourcesAndThirdPartyNoticesAreBundled() {
        XCTAssertNotNil(Bundle.main.url(forResource: "bull-moo", withExtension: "wav"))
        XCTAssertNotNil(Bundle.main.url(forResource: "bear-growl", withExtension: "wav"))
        XCTAssertNotNil(Bundle.main.url(forResource: "GRDB-MIT", withExtension: "txt"))
        XCTAssertNotNil(
            Bundle.main.url(forResource: "THIRD_PARTY_NOTICES", withExtension: "md")
        )
    }
}
