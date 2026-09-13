@preconcurrency import AVFoundation
import Foundation
@preconcurrency import MediaPlayer
import OneBoxDesignSystem
import XCTest

@testable import OneBox

final class AppCompositionTests: XCTestCase {
    @MainActor
    func testUITestingWindowSizeOverrides() {
        XCTAssertEqual(
            AppComposition.UITestingConfiguration.forcedWindowSize(
                arguments: ["OneBox", "--ui-testing", "--ui-minimum"]
            ),
            DesignMetrics.minimumWindowSize
        )
        XCTAssertEqual(
            AppComposition.UITestingConfiguration.forcedWindowSize(
                arguments: ["OneBox", "--ui-testing", "--ui-default"]
            ),
            DesignMetrics.defaultWindowSize
        )
        XCTAssertNil(
            AppComposition.UITestingConfiguration.forcedWindowSize(
                arguments: ["OneBox", "--ui-testing"]
            )
        )
        #if !DEBUG
            XCTAssertNil(
                AppComposition.UITestingConfiguration.forcedWindowSize(
                    arguments: ["OneBox", "--ui-minimum"]
                )
            )
        #endif
    }

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

    @MainActor
    func testUITestingConfigurationRequiresAnAbsoluteDataRoot() {
        XCTAssertThrowsError(
            try AppComposition.UITestingConfiguration.resolve(
                arguments: ["OneBox", "--ui-testing"],
                environment: [:]
            )
        ) { error in
            XCTAssertEqual(
                error as? AppComposition.UITestingConfigurationError,
                .missingAbsoluteDataRoot
            )
        }

        XCTAssertThrowsError(
            try AppComposition.UITestingConfiguration.resolve(
                arguments: ["OneBox", "--ui-testing"],
                environment: ["ONEBOX_UI_TEST_DATA_ROOT": "relative/path"]
            )
        ) { error in
            XCTAssertEqual(
                error as? AppComposition.UITestingConfigurationError,
                .missingAbsoluteDataRoot
            )
        }
    }

    @MainActor
    func testUITestingConfigurationIgnoresEnvironmentWithoutLaunchFlag() throws {
        let configuration = try AppComposition.UITestingConfiguration.resolve(
            arguments: ["OneBox"],
            environment: ["ONEBOX_UI_TEST_DATA_ROOT": "/should/not/be/consumed"]
        )

        XCTAssertNil(configuration)
    }

    @MainActor
    func testReduceMotionOverrideRequiresTheUITestingLaunchFlag() {
        XCTAssertFalse(
            AppComposition.UITestingConfiguration.forcesReduceMotion(
                arguments: ["OneBox", "--ui-reduce-motion"]
            )
        )
        XCTAssertFalse(
            AppComposition.UITestingConfiguration.forcesReduceMotion(
                arguments: ["OneBox", "--ui-testing"]
            )
        )
        XCTAssertTrue(
            AppComposition.UITestingConfiguration.forcesReduceMotion(
                arguments: ["OneBox", "--ui-testing", "--ui-reduce-motion"]
            )
        )
    }

    @MainActor
    func testUITestingConfigurationRejectsAbsoluteNonTemporaryPath() {
        XCTAssertThrowsError(
            try AppComposition.UITestingConfiguration.resolve(
                arguments: ["OneBox", "--ui-testing"],
                environment: [
                    "ONEBOX_UI_TEST_DATA_ROOT": "/Applications/OneBox-UITests-Forbidden"
                ]
            )
        ) { error in
            XCTAssertEqual(
                error as? AppComposition.UITestingConfigurationError,
                .unsafeDataRoot
            )
        }
    }

    @MainActor
    func testUITestingConfigurationUsesOnlyTheInjectedDataRoot() throws {
        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "OneBox-AppCompositionTests-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let configuration = try XCTUnwrap(
            AppComposition.UITestingConfiguration.resolve(
                arguments: ["OneBox", "--ui-testing"],
                environment: ["ONEBOX_UI_TEST_DATA_ROOT": rootURL.path]
            )
        )

        XCTAssertEqual(
            configuration.applicationSupportDirectoryURL,
            rootURL.standardizedFileURL.resolvingSymlinksInPath()
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: rootURL.path))
    }

    @MainActor
    func testUITestingConfigurationAcceptsOnlyARegularPodPinFixtureInsideDataRoot() throws {
        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "OneBox-AppCompositionFixtureTests-\(UUID().uuidString)",
            isDirectory: true
        )
        let fixtureDirectoryURL = rootURL.appendingPathComponent("Fixtures", isDirectory: true)
        let fixtureURL = fixtureDirectoryURL.appendingPathComponent(
            "podpin-sample.m4a",
            isDirectory: false
        )
        try FileManager.default.createDirectory(
            at: fixtureDirectoryURL,
            withIntermediateDirectories: true
        )
        try Data([0]).write(to: fixtureURL)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let configuration = try XCTUnwrap(
            AppComposition.UITestingConfiguration.resolve(
                arguments: ["OneBox", "--ui-testing"],
                environment: [
                    "ONEBOX_UI_TEST_DATA_ROOT": rootURL.path,
                    "ONEBOX_UI_TEST_PODPIN_FIXTURE_AUDIO": fixtureURL.path,
                ]
            )
        )

        XCTAssertEqual(
            configuration.podPinFixtureAudioURL,
            fixtureURL.standardizedFileURL.resolvingSymlinksInPath()
        )
    }

    @MainActor
    func testUITestingConfigurationRejectsPodPinFixtureOutsideDataRoot() throws {
        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "OneBox-AppCompositionFixtureRoot-\(UUID().uuidString)",
            isDirectory: true
        )
        let outsideFixtureURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "OneBox-AppCompositionFixtureOutside-\(UUID().uuidString).m4a",
            isDirectory: false
        )
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try Data([0]).write(to: outsideFixtureURL)
        defer {
            try? FileManager.default.removeItem(at: rootURL)
            try? FileManager.default.removeItem(at: outsideFixtureURL)
        }

        XCTAssertThrowsError(
            try AppComposition.UITestingConfiguration.resolve(
                arguments: ["OneBox", "--ui-testing"],
                environment: [
                    "ONEBOX_UI_TEST_DATA_ROOT": rootURL.path,
                    "ONEBOX_UI_TEST_PODPIN_FIXTURE_AUDIO": outsideFixtureURL.path,
                ]
            )
        ) { error in
            XCTAssertEqual(
                error as? AppComposition.UITestingConfigurationError,
                .unsafePodPinFixtureAudio
            )
        }
    }
}
