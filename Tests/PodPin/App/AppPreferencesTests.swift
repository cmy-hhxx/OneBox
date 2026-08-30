import Combine
import Foundation
import XCTest

@testable import PodPinTool

@MainActor
final class AppPreferencesTests: XCTestCase {
    func testNowPlayingContentOpacityRestoresClampsAndPersists() throws {
        let suiteName = "AppPreferencesTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(0.65, forKey: "podpin.nowPlayingContentOpacity")
        let preferences = AppPreferences(defaults: defaults)

        XCTAssertEqual(preferences.nowPlayingContentOpacity, 0.65)

        preferences.nowPlayingContentOpacity = 0.05
        XCTAssertEqual(preferences.nowPlayingContentOpacity, 0.45)
        XCTAssertEqual(defaults.double(forKey: "podpin.nowPlayingContentOpacity"), 0.45)
    }

    func testNowPlayingContentOpacityPublishesChanges() throws {
        let suiteName = "AppPreferencesOpacityPublisherTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let preferences = AppPreferences(defaults: defaults)
        var publishedValues = [Double]()
        let cancellable = preferences.$nowPlayingContentOpacity.sink { publishedValues.append($0) }

        preferences.nowPlayingContentOpacity = 0.45

        XCTAssertEqual(publishedValues.last, 0.45)
        withExtendedLifetime(cancellable) {}
    }

    func testPlaybackTimeFormatterUsesAnHourOnlyWhenNeeded() {
        XCTAssertEqual(PlaybackTimeFormatter.string(for: nil), "—")
        XCTAssertEqual(PlaybackTimeFormatter.string(for: 0), "0:00")
        XCTAssertEqual(PlaybackTimeFormatter.string(for: 3_569), "59:29")
        XCTAssertEqual(PlaybackTimeFormatter.string(for: 3_723), "1:02:03")
        XCTAssertEqual(PlaybackTimeFormatter.string(for: -1), "—")
        XCTAssertEqual(PlaybackTimeFormatter.string(for: .nan), "—")
        XCTAssertEqual(
            PlaybackTimeFormatter.remainingString(current: 60, duration: 3_600),
            "−59:00"
        )
        XCTAssertEqual(
            PlaybackTimeFormatter.remainingString(current: 3_600, duration: 3_600),
            "−0:00"
        )
        XCTAssertEqual(
            PlaybackTimeFormatter.remainingString(current: nil, duration: 3_600),
            "—"
        )
    }

    func testPlaybackRateCycleAdvancesAndWraps() {
        XCTAssertEqual(AppPreferences.nextPlaybackRate(after: 0.75), 1)
        XCTAssertEqual(AppPreferences.nextPlaybackRate(after: 1), 1.25)
        XCTAssertEqual(AppPreferences.nextPlaybackRate(after: 1.25), 1.5)
        XCTAssertEqual(AppPreferences.nextPlaybackRate(after: 1.5), 2)
        XCTAssertEqual(AppPreferences.nextPlaybackRate(after: 2), 0.75)
    }

    func testPlaybackVolumeClampsAndRestores() throws {
        let suiteName = "AppPreferencesVolumeTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let preferences = AppPreferences(defaults: defaults)
        preferences.playbackVolume = 1.4

        XCTAssertEqual(preferences.playbackVolume, 1)
        XCTAssertEqual(defaults.double(forKey: "podpin.playbackVolume"), 1)

        preferences.playbackVolume = -0.2
        XCTAssertEqual(preferences.playbackVolume, 0)
        XCTAssertEqual(AppPreferences(defaults: defaults).playbackVolume, 0)
    }

    func testLastLibraryCollectionPersistsAcrossPreferenceInstances() throws {
        let suiteName = "AppPreferencesCollectionTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let folderID = UUID()
        let preferences = AppPreferences(defaults: defaults)
        preferences.lastLibraryCollection = .folder(folderID)

        XCTAssertEqual(AppPreferences(defaults: defaults).lastLibraryCollection, .folder(folderID))
    }
}
