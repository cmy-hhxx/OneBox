@preconcurrency import AVFoundation
import Foundation
import XCTest

@testable import PodPinTool

final class AudioPlaybackControllerTests: XCTestCase {
    @MainActor
    func testLoadUsesInjectedPlayerFactory() async throws {
        let importer = try FixtureContentImporter.bundled()
        let metadata = try await importer.probe(url: FixtureContentImporter.sampleURL).primaryItem
        let stream = try await importer.resolveStream(for: metadata)
        let item = AudioItem(
            platform: metadata.platform,
            contentID: "injected-player-factory",
            sourceURL: metadata.sourceURL,
            title: metadata.title,
            duration: metadata.duration
        )
        var factoryCallCount = 0
        let controller = AudioPlaybackController { playerItem in
            factoryCallCount += 1
            return AVPlayer(playerItem: playerItem)
        }

        controller.load(item: item, url: stream.url)

        XCTAssertEqual(factoryCallCount, 1)
        controller.stop()
    }

    @MainActor
    func testSuccessfulSeekForcesPlaybackPositionPersistence() async throws {
        let importer = try FixtureContentImporter.bundled()
        let metadata = try await importer.probe(url: FixtureContentImporter.sampleURL).primaryItem
        let stream = try await importer.resolveStream(for: metadata)
        let item = AudioItem(
            platform: metadata.platform,
            contentID: metadata.contentID,
            sourceURL: metadata.sourceURL,
            title: metadata.title,
            author: metadata.author,
            duration: metadata.duration
        )
        let controller = AudioPlaybackController()
        let persisted = expectation(description: "seek position is persisted")

        controller.onPlaybackPositionChanged = { id, position, _, force in
            guard id == item.id, force, abs(position - 3) < 0.1 else { return }
            persisted.fulfill()
        }
        controller.load(item: item, url: stream.url, autoplay: false)

        try await waitUntil { controller.state == .paused }
        controller.seek(to: 3)

        await fulfillment(of: [persisted], timeout: 2)
        XCTAssertEqual(controller.currentTime, 3, accuracy: 0.1)
    }

    @MainActor
    func testPausingWhileLoadingPreventsAutoplayAfterReadiness() async throws {
        let importer = try FixtureContentImporter.bundled()
        let metadata = try await importer.probe(url: FixtureContentImporter.sampleURL).primaryItem
        let stream = try await importer.resolveStream(for: metadata)
        let item = AudioItem(
            platform: metadata.platform,
            contentID: "loading-pause",
            sourceURL: metadata.sourceURL,
            title: metadata.title,
            author: metadata.author,
            duration: metadata.duration
        )
        let controller = AudioPlaybackController()

        controller.load(item: item, url: stream.url, autoplay: true)
        controller.pause()

        try await Task.sleep(for: .milliseconds(250))
        XCTAssertEqual(controller.state, .paused)
        XCTAssertFalse(controller.isPlaying)
    }

    @MainActor
    func testAutoplayExpressesPlaybackIntentAndAppliesRateWhileBuffering() async throws {
        let importer = try FixtureContentImporter.bundled()
        let metadata = try await importer.probe(url: FixtureContentImporter.sampleURL).primaryItem
        let stream = try await importer.resolveStream(for: metadata)
        let item = AudioItem(
            platform: metadata.platform,
            contentID: "buffering-transition",
            sourceURL: metadata.sourceURL,
            title: metadata.title,
            author: metadata.author,
            duration: metadata.duration
        )
        let controller = AudioPlaybackController()
        var phases = [PlaybackPhase]()
        var didChangeRateWhileBuffering = false
        controller.onStateChanged = {
            phases.append(controller.state)
            if controller.state == .buffering, !didChangeRateWhileBuffering {
                didChangeRateWhileBuffering = true
                controller.setRate(1.5)
            }
        }

        controller.load(item: item, url: stream.url, autoplay: true)

        // Headless XCTest does not guarantee an audible output route. Reaching
        // buffering still proves that autoplay intent survived asset readiness.
        try await waitUntil {
            controller.state == .buffering || controller.state == .playing
        }
        XCTAssertTrue(phases.contains(.buffering))
        XCTAssertTrue(didChangeRateWhileBuffering)
        XCTAssertEqual(controller.rate, 1.5)
        XCTAssertTrue(controller.state.hasPlaybackIntent)
    }

    @MainActor
    func testListeningHistoryPreservesGapCreatedBySeeking() async throws {
        let importer = try FixtureContentImporter.bundled()
        let metadata = try await importer.probe(url: FixtureContentImporter.sampleURL).primaryItem
        let stream = try await importer.resolveStream(for: metadata)
        let item = AudioItem(
            platform: metadata.platform,
            contentID: "listening-gap",
            sourceURL: metadata.sourceURL,
            title: metadata.title,
            author: metadata.author,
            duration: metadata.duration
        )
        let controller = AudioPlaybackController()

        controller.load(item: item, url: stream.url, autoplay: true)
        try await waitUntil { controller.state == .playing }
        try await waitUntil {
            (controller.listeningHistory.intervals.first?.end ?? 0) > 0.25
        }
        controller.pause()
        let firstIntervalEnd = try XCTUnwrap(controller.listeningHistory.intervals.first?.end)

        controller.seek(to: 5)
        try await waitUntil { controller.currentTime > 4.8 }
        controller.play()
        try await waitUntil { controller.state == .playing }
        try await waitUntil {
            controller.listeningHistory.intervals.contains { $0.start > 4.5 && $0.end > 5.2 }
        }
        controller.pause()

        XCTAssertEqual(controller.listeningHistory.intervals.count, 2)
        XCTAssertLessThan(firstIntervalEnd, 2)
        XCTAssertGreaterThan(controller.listeningHistory.intervals[1].start, 4.5)
        XCTAssertFalse(controller.listeningHistory.isComplete(duration: metadata.duration ?? 8))
    }

    @MainActor
    func testFinishedItemEntersReplayPendingAndIgnoresASecondReplayRequest() async throws {
        let importer = try FixtureContentImporter.bundled()
        let metadata = try await importer.probe(url: FixtureContentImporter.sampleURL).primaryItem
        let stream = try await importer.resolveStream(for: metadata)
        let item = AudioItem(
            platform: metadata.platform,
            contentID: "finished-replay",
            sourceURL: metadata.sourceURL,
            title: metadata.title,
            author: metadata.author,
            duration: metadata.duration
        )
        let controller = AudioPlaybackController()

        controller.load(item: item, url: stream.url, autoplay: false)
        try await waitUntil { controller.state == .paused }
        controller.seek(to: 7.7)
        try await waitUntil { controller.currentTime > 7.5 }

        controller.play()
        try await waitUntil({ controller.state == .finished }, timeout: 3)

        controller.play()
        XCTAssertEqual(controller.state, .replayPending)
        controller.play()
        XCTAssertEqual(controller.state, .replayPending)

        try await waitUntil { controller.state == .playing }
    }

    @MainActor
    private func waitUntil(
        _ condition: @escaping @MainActor () -> Bool,
        timeout: TimeInterval = 2
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            guard Date() < deadline else {
                XCTFail("Timed out waiting for the audio player")
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}
