@preconcurrency import AVFoundation
import Foundation
@preconcurrency import MediaPlayer
import XCTest

@testable import PodPinTool

private final class TestApplicationSupportFileManager: FileManager, @unchecked Sendable {
    let applicationSupportURL: URL
    private(set) var applicationSupportURLRequestCount = 0

    init(applicationSupportURL: URL) {
        self.applicationSupportURL = applicationSupportURL
        super.init()
    }

    override func urls(
        for directory: SearchPathDirectory,
        in domainMask: SearchPathDomainMask
    ) -> [URL] {
        guard directory == .applicationSupportDirectory, domainMask == .userDomainMask else {
            return super.urls(for: directory, in: domainMask)
        }
        applicationSupportURLRequestCount += 1
        return [applicationSupportURL]
    }
}

@MainActor
private final class TestPodPinPlatform: PodPinPlatformProviding {
    private let preferences: UserDefaults
    private let manager: FileManager
    private let commandCenter: MPRemoteCommandCenter
    private let infoCenter: MPNowPlayingInfoCenter

    private(set) var legacyPreferencesRequestCount = 0
    private(set) var fileManagerRequestCount = 0
    private(set) var remoteCommandCenterRequestCount = 0
    private(set) var nowPlayingInfoCenterRequestCount = 0
    private(set) var audioPlayerRequestCount = 0

    init(fileManager: FileManager = FileManager()) {
        let suiteName = "PodPinModuleTests-\(UUID().uuidString)"
        preferences = UserDefaults(suiteName: suiteName)!
        manager = fileManager
        commandCenter = .shared()
        infoCenter = .default()
    }

    var legacyPreferences: UserDefaults {
        legacyPreferencesRequestCount += 1
        return preferences
    }

    var fileManager: FileManager {
        fileManagerRequestCount += 1
        return manager
    }

    var remoteCommandCenter: MPRemoteCommandCenter {
        remoteCommandCenterRequestCount += 1
        return commandCenter
    }

    var nowPlayingInfoCenter: MPNowPlayingInfoCenter {
        nowPlayingInfoCenterRequestCount += 1
        return infoCenter
    }

    func makeAudioPlayer(item: AVPlayerItem) -> AVPlayer {
        audioPlayerRequestCount += 1
        return AVPlayer(playerItem: item)
    }

    var requestCounts: [Int] {
        [
            legacyPreferencesRequestCount,
            fileManagerRequestCount,
            remoteCommandCenterRequestCount,
            nowPlayingInfoCenterRequestCount,
            audioPlayerRequestCount,
        ]
    }
}

@MainActor
final class PodPinModuleTests: XCTestCase {
    func testRegistrationUsesStableIdentityWithoutCreatingLifecycle() {
        let platform = TestPodPinPlatform()

        let registration = PodPinModule.makeRegistration(
            platform: platform,
            debugFixtureAudioURL: nil,
            externalToolsDirectoryURL: nil
        )

        XCTAssertEqual(registration.id.rawValue, "podpin")
        XCTAssertEqual(registration.displayName, "PodPin")
        XCTAssertEqual(platform.requestCounts, [0, 0, 0, 0, 0])
    }

    func testEachRegistrationOwnsAnIndependentLazySession() async {
        let platform = TestPodPinPlatform()
        let firstRegistration = PodPinModule.makeRegistration(
            platform: platform,
            debugFixtureAudioURL: nil,
            externalToolsDirectoryURL: nil
        )
        let secondRegistration = PodPinModule.makeRegistration(
            platform: platform,
            debugFixtureAudioURL: nil,
            externalToolsDirectoryURL: nil
        )
        XCTAssertEqual(platform.requestCounts, [0, 0, 0, 0, 0])

        _ = firstRegistration.content()
        XCTAssertEqual(platform.requestCounts, [1, 1, 1, 1, 0])

        _ = firstRegistration.content()
        XCTAssertEqual(platform.requestCounts, [1, 1, 1, 1, 0])

        _ = secondRegistration.content()
        XCTAssertEqual(platform.requestCounts, [2, 2, 2, 2, 0])

        await firstRegistration.prepareForApplicationTermination()
        await secondRegistration.prepareForApplicationTermination()
    }

    func testLifecycleUsesInjectedFileManagerForDatabaseAndMediaStore() async {
        let applicationSupportURL = FileManager.default.temporaryDirectory.appending(
            path: "PodPinModuleTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: applicationSupportURL) }
        let fileManager = TestApplicationSupportFileManager(
            applicationSupportURL: applicationSupportURL
        )
        let session = PodPinModuleSession(
            platform: TestPodPinPlatform(fileManager: fileManager),
            debugFixtureAudioURL: nil,
            externalToolsDirectoryURL: nil
        )

        let lifecycle = session.contentLifecycle()
        await lifecycle.store.start()

        XCTAssertEqual(fileManager.applicationSupportURLRequestCount, 2)
        let libraryRoot = applicationSupportURL.appending(
            path: MarketDatabase.applicationSupportFolderName,
            directoryHint: .isDirectory
        )
        XCTAssertTrue(
            fileManager.fileExists(
                atPath: libraryRoot.appending(path: MarketDatabase.defaultFileName).path
            )
        )
        XCTAssertTrue(
            fileManager.fileExists(
                atPath: libraryRoot.appending(path: PodPinMediaStore.mediaDirectoryName).path
            )
        )

        await session.shutdown()
    }

    func testSessionCreatesOneLifecycleLazilyAndCanRestartAfterShutdown() async {
        let session = PodPinModuleSession(
            platform: TestPodPinPlatform(),
            debugFixtureAudioURL: nil,
            externalToolsDirectoryURL: nil
        )
        XCTAssertFalse(session.hasActiveLifecycle)

        let firstLifecycle = session.contentLifecycle()
        XCTAssertTrue(session.hasActiveLifecycle)
        XCTAssertTrue(firstLifecycle === session.contentLifecycle())

        await session.shutdown()
        XCTAssertFalse(session.hasActiveLifecycle)

        let restartedLifecycle = session.contentLifecycle()
        XCTAssertFalse(firstLifecycle === restartedLifecycle)
        await session.shutdown()
        XCTAssertFalse(session.hasActiveLifecycle)
    }
}
