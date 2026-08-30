import Foundation
import XCTest

@testable import StockWatchTool

@MainActor
final class AlertSoundPlayerTests: XCTestCase {
    func testEnabledSoundStopsCurrentPlaybackBeforeUsingDirectionResource() {
        let platform = SoundPlatformProbe()
        let player = AlertSoundPlayer(platform: platform)

        player.play(.rising, isEnabled: true)
        player.play(.falling, isEnabled: true)
        player.stop()

        XCTAssertEqual(
            platform.operations,
            [
                .stop,
                .play("bull-moo.wav"),
                .stop,
                .play("bear-growl.wav"),
                .stop,
            ]
        )
    }

    func testDisabledOppositeDirectionStopsCurrentPlaybackWithoutStartingReplacement() {
        let platform = SoundPlatformProbe()
        let player = AlertSoundPlayer(platform: platform)

        player.play(.rising, isEnabled: true)
        player.play(.falling, isEnabled: false)

        XCTAssertEqual(
            platform.operations,
            [
                .stop,
                .play("bull-moo.wav"),
                .stop,
            ]
        )
    }
}

@MainActor
private final class SoundPlatformProbe: StockWatchPlatformClient {
    enum Operation: Equatable {
        case play(String)
        case stop
    }

    private(set) var operations: [Operation] = []

    func copyText(_ text: String) -> Bool { true }
    func revealDirectory(_ directory: URL) -> Bool { true }

    func playAlertSound(at fileURL: URL) -> Bool {
        operations.append(.play(fileURL.lastPathComponent))
        return true
    }

    func stopAlertSound() {
        operations.append(.stop)
    }
}
