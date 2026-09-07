import Foundation
import XCTest

enum OneBoxUITestSupport {
    static let dataRootEnvironmentKey = "ONEBOX_UI_TEST_DATA_ROOT"
    static let podPinFixtureAudioEnvironmentKey = "ONEBOX_UI_TEST_PODPIN_FIXTURE_AUDIO"
    static let reduceMotionLaunchArgument = "--ui-reduce-motion"
    static let podPinFixtureURLText = "https://fixture.podpin.local/welcome"
    static let podPinCollectionFixtureURLText = "https://fixture.podpin.local/collection"

    static func makeDataRoot(prefix: String) throws -> URL {
        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "\(prefix)-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        return rootURL
    }

    @MainActor
    static func configure(
        _ application: XCUIApplication,
        dataRootURL: URL,
        additionalArguments: [String] = []
    ) throws {
        if !application.launchArguments.contains("--ui-testing") {
            application.launchArguments.append("--ui-testing")
        }
        application.launchArguments.append(contentsOf: additionalArguments)
        application.launchEnvironment[dataRootEnvironmentKey] = dataRootURL.path
        application.launchEnvironment[podPinFixtureAudioEnvironmentKey] = try installPodPinFixture(
            into: dataRootURL
        ).path
    }

    static func cleanUp(dataRootURL: URL) {
        let suiteComponent = dataRootURL.lastPathComponent
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        for tool in ["PodPin", "StockWatch"] {
            UserDefaults.standard.removePersistentDomain(
                forName: "com.cmy.OneBox.UITests.\(suiteComponent).\(tool)"
            )
        }
        try? FileManager.default.removeItem(at: dataRootURL)
    }

    private static func installPodPinFixture(into dataRootURL: URL) throws -> URL {
        let testBundle = Bundle(for: OneBoxUITestBundleToken.self)
        let sourceURL = try XCTUnwrap(
            testBundle.url(forResource: "podpin-sample", withExtension: "m4a"),
            "The UI test bundle must contain the local PodPin audio fixture."
        )
        let fixtureDirectoryURL = dataRootURL.appendingPathComponent(
            "TestFixtures",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: fixtureDirectoryURL,
            withIntermediateDirectories: true
        )
        let destinationURL = fixtureDirectoryURL.appendingPathComponent(
            "podpin-sample.m4a",
            isDirectory: false
        )
        if !FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        }
        return destinationURL
    }
}

private final class OneBoxUITestBundleToken {}
