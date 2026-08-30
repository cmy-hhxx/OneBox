import AppKit
import CoreGraphics
import Foundation
@preconcurrency import MediaPlayer
import XCTest

@testable import PodPinTool

private actor ArtworkLoadCounter {
    private(set) var count = 0

    func load() -> NowPlayingDecodedArtwork {
        count += 1
        return makeDecodedArtwork()
    }
}

private func makeDecodedArtwork() -> NowPlayingDecodedArtwork {
    let context = CGContext(
        data: nil,
        width: 24,
        height: 24,
        bitsPerComponent: 8,
        bytesPerRow: 24 * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    return NowPlayingDecodedArtwork(image: context.makeImage()!)
}

final class NowPlayingControllerTests: XCTestCase {
    @MainActor
    func testRepeatedTimeUpdatesReuseArtworkForSameItemAndPath() async {
        let artworkLoads = ArtworkLoadCounter()
        let controller = NowPlayingController(
            commandCenter: .shared(),
            nowPlayingInfoCenter: .default()
        ) { _ in
            await artworkLoads.load()
        }
        let item = AudioItem(
            platform: .fixture,
            contentID: "now-playing-artwork",
            sourceURL: URL(string: "https://fixture.podpin.local/artwork")!,
            title: "Artwork cache"
        )
        let artworkURL = URL(fileURLWithPath: "/tmp/podpin-artwork.png")

        controller.publish(
            item: item,
            time: 1,
            duration: 30,
            rate: 1,
            isPlaying: true,
            artworkURL: artworkURL
        )
        controller.publish(
            item: item,
            time: 1.5,
            duration: 30,
            rate: 1,
            isPlaying: true,
            artworkURL: artworkURL
        )
        await controller.waitForPendingArtwork()

        let loadCount = await artworkLoads.count
        XCTAssertEqual(loadCount, 1)
        await controller.deactivate()
    }

    @MainActor
    func testArtworkRequestCanRunOffMainThread() async {
        let infoCenter = MPNowPlayingInfoCenter.default()
        let controller = NowPlayingController(
            commandCenter: .shared(),
            nowPlayingInfoCenter: infoCenter
        ) { _ in
            makeDecodedArtwork()
        }
        let item = AudioItem(
            platform: .fixture,
            contentID: "now-playing-background-artwork",
            sourceURL: URL(string: "https://fixture.podpin.local/background-artwork")!,
            title: "Background artwork"
        )

        controller.publish(
            item: item,
            time: 0,
            duration: 30,
            rate: 1,
            isPlaying: true,
            artworkURL: URL(fileURLWithPath: "/tmp/podpin-background-artwork.png")
        )
        await controller.waitForPendingArtwork()

        guard
            let artwork = infoCenter.nowPlayingInfo?[
                MPMediaItemPropertyArtwork] as? MPMediaItemArtwork
        else {
            await controller.deactivate()
            return XCTFail("Expected Now Playing artwork")
        }

        let requestFinished = expectation(
            description: "Artwork request finishes off the main thread")
        DispatchQueue.global(qos: .userInitiated).async {
            _ = artwork.image(at: NSSize(width: 24, height: 24))
            requestFinished.fulfill()
        }
        await fulfillment(of: [requestFinished], timeout: 1)
        await controller.deactivate()
    }

    @MainActor
    func testDeactivationCancelsAndDrainsArtworkLoad() async {
        let started = expectation(description: "artwork load started")
        let cancelled = expectation(description: "artwork load cancelled")
        let controller = NowPlayingController { _ in
            started.fulfill()
            do {
                try await Task.sleep(for: .seconds(3_600))
            } catch {
                cancelled.fulfill()
            }
            return nil
        }
        let item = AudioItem(
            platform: .fixture,
            contentID: "now-playing-cancel-artwork",
            sourceURL: URL(string: "https://fixture.podpin.local/cancel-artwork")!,
            title: "Cancel artwork"
        )
        controller.publish(
            item: item,
            time: 0,
            duration: 30,
            rate: 1,
            isPlaying: false,
            artworkURL: URL(fileURLWithPath: "/tmp/podpin-cancel-artwork.png")
        )
        await fulfillment(of: [started], timeout: 1)

        await controller.deactivate()

        await fulfillment(of: [cancelled], timeout: 1)
    }

    @MainActor
    func testRepeatedActivationAndDeactivationDoNotLeakCommandHandlers() async {
        let commandCenter = MPRemoteCommandCenter.shared()
        let infoCenter = MPNowPlayingInfoCenter.default()
        let controller = NowPlayingController(
            commandCenter: commandCenter,
            nowPlayingInfoCenter: infoCenter
        )
        await controller.deactivate()

        controller.activate()
        XCTAssertEqual(controller.installedCommandHandlerCount, 7)
        controller.activate()
        XCTAssertEqual(controller.installedCommandHandlerCount, 7)

        let item = AudioItem(
            platform: .fixture,
            contentID: "now-playing-cleanup",
            sourceURL: URL(string: "https://fixture.podpin.local/cleanup")!,
            title: "Cleanup"
        )
        controller.publish(
            item: item,
            time: 5,
            duration: 30,
            rate: 1,
            isPlaying: true
        )
        XCTAssertNotNil(infoCenter.nowPlayingInfo)

        await controller.deactivate()
        XCTAssertEqual(controller.installedCommandHandlerCount, 0)
        XCTAssertNil(infoCenter.nowPlayingInfo)
        XCTAssertEqual(infoCenter.playbackState, .stopped)
        XCTAssertFalse(commandCenter.playCommand.isEnabled)
        XCTAssertFalse(commandCenter.pauseCommand.isEnabled)
        XCTAssertFalse(commandCenter.togglePlayPauseCommand.isEnabled)
        XCTAssertFalse(commandCenter.skipBackwardCommand.isEnabled)
        XCTAssertFalse(commandCenter.skipForwardCommand.isEnabled)
        XCTAssertFalse(commandCenter.changePlaybackPositionCommand.isEnabled)
        XCTAssertFalse(commandCenter.changePlaybackRateCommand.isEnabled)

        await controller.deactivate()
        XCTAssertEqual(controller.installedCommandHandlerCount, 0)
        controller.activate()
        XCTAssertEqual(controller.installedCommandHandlerCount, 7)
        await controller.deactivate()
    }
}
