import Combine
import Foundation
import XCTest

@testable import PodPinTool

@MainActor
final class PlaybackPresentationModelTests: XCTestCase {
    func testPlaybackTicksDoNotPublishTheLibraryStore() throws {
        let defaultsName = "PlaybackPresentationModelTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsName))
        defer { defaults.removePersistentDomain(forName: defaultsName) }

        let store = PodPinStore(preferences: AppPreferences(defaults: defaults))
        var storePublicationCount = 0
        let cancellable = store.objectWillChange.sink { _ in
            storePublicationCount += 1
        }
        var identityPublicationCount = 0
        let identityCancellable = store.playbackPresentation.identity.objectWillChange.sink { _ in
            identityPublicationCount += 1
        }
        var timelinePublicationCount = 0
        let timelineCancellable = store.playbackPresentation.timeline.objectWillChange.sink { _ in
            timelinePublicationCount += 1
        }
        defer {
            cancellable.cancel()
            identityCancellable.cancel()
            timelineCancellable.cancel()
        }

        store.playbackPresentation.update(
            PlaybackSnapshot(
                item: nil,
                phase: .playing,
                currentTime: 0,
                duration: 120,
                rate: 1
            )
        )
        identityPublicationCount = 0
        timelinePublicationCount = 0
        store.playbackPresentation.update(
            PlaybackSnapshot(
                item: nil,
                phase: .playing,
                currentTime: 0.5,
                duration: 120,
                rate: 1
            )
        )

        XCTAssertEqual(storePublicationCount, 0)
        XCTAssertEqual(identityPublicationCount, 0)
        XCTAssertEqual(timelinePublicationCount, 1)
        XCTAssertEqual(store.playbackPresentation.snapshot.currentTime, 0.5)
    }

    func testVolumeUpdatesPublishOnlyTheOutputSession() {
        let presentation = PlaybackPresentationModel()
        var identityPublicationCount = 0
        var timelinePublicationCount = 0
        var outputPublicationCount = 0
        let identityCancellable = presentation.identity.objectWillChange.sink { _ in
            identityPublicationCount += 1
        }
        let timelineCancellable = presentation.timeline.objectWillChange.sink { _ in
            timelinePublicationCount += 1
        }
        let outputCancellable = presentation.output.objectWillChange.sink { _ in
            outputPublicationCount += 1
        }
        defer {
            identityCancellable.cancel()
            timelineCancellable.cancel()
            outputCancellable.cancel()
        }

        presentation.update(.empty, outputVolume: 0.42)

        XCTAssertEqual(identityPublicationCount, 0)
        XCTAssertEqual(timelinePublicationCount, 0)
        XCTAssertEqual(outputPublicationCount, 1)
        XCTAssertEqual(presentation.output.snapshot.volume, 0.42)
    }
}
