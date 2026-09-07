import AsciiArtTool
import Foundation
import OneBoxDesignSystem
import OneBoxRuntime
import PodPinTool
import StockWatchTool

enum AppComposition {
    static func makeCatalog(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> ToolCatalog {
        let uiTesting: UITestingConfiguration?
        do {
            uiTesting = try UITestingConfiguration.resolve(
                arguments: arguments,
                environment: environment
            )
        } catch {
            preconditionFailure("Invalid OneBox UI test configuration: \(error)")
        }

        let podPinPlatform = PodPinSystemPlatformAdapter(
            legacyPreferences: uiTesting?.podPinPreferences
        )
        return ToolCatalog(registrations: [
            AsciiArtModule.makeRegistration(
                deviceProvider: SystemAsciiMetalDeviceProvider()
            ),
            StockWatchModule.makeRegistration(
                platform: MacStockWatchPlatformClient(),
                applicationSupportDirectoryURL: uiTesting?.applicationSupportDirectoryURL,
                preferences: uiTesting?.stockWatchPreferences,
                allowsNetworkAccess: uiTesting == nil
            ),
            PodPinModule.makeRegistration(
                platform: podPinPlatform,
                debugFixtureAudioURL: uiTesting?.podPinFixtureAudioURL
                    ?? podPinPlatform.debugFixtureAudioURL,
                externalToolsDirectoryURL: uiTesting == nil
                    ? podPinPlatform.externalToolsDirectoryURL
                    : nil,
                applicationSupportDirectoryURL: uiTesting?.applicationSupportDirectoryURL,
                allowsNetworkAccess: uiTesting == nil
            ),
        ])
    }
}

extension AppComposition {
    struct UITestingConfiguration {
        static let launchFlag = "--ui-testing"
        static let reduceMotionLaunchFlag = "--ui-reduce-motion"
        static let dataRootEnvironmentKey = "ONEBOX_UI_TEST_DATA_ROOT"
        static let podPinFixtureAudioEnvironmentKey =
            "ONEBOX_UI_TEST_PODPIN_FIXTURE_AUDIO"

        let applicationSupportDirectoryURL: URL
        let podPinFixtureAudioURL: URL?
        let podPinPreferences: UserDefaults
        let stockWatchPreferences: UserDefaults

        static func forcesReduceMotion(arguments: [String]) -> Bool {
            arguments.contains(launchFlag) && arguments.contains(reduceMotionLaunchFlag)
        }

        static func forcedWindowSize(arguments: [String]) -> CGSize? {
            #if !DEBUG
                guard arguments.contains(launchFlag) else { return nil }
            #endif
            if arguments.contains("--ui-minimum") {
                return DesignMetrics.minimumWindowSize
            }
            if arguments.contains("--ui-default") {
                return DesignMetrics.defaultWindowSize
            }
            return nil
        }

        static func resolve(
            arguments: [String],
            environment: [String: String]
        ) throws -> UITestingConfiguration? {
            guard arguments.contains(launchFlag) else { return nil }
            guard
                let path = environment[dataRootEnvironmentKey],
                !path.isEmpty,
                NSString(string: path).isAbsolutePath
            else {
                throw UITestingConfigurationError.missingAbsoluteDataRoot
            }

            let rootURL = URL(fileURLWithPath: path, isDirectory: true)
                .standardizedFileURL
                .resolvingSymlinksInPath()
            let temporaryDirectoryURL = FileManager.default.temporaryDirectory
                .standardizedFileURL
                .resolvingSymlinksInPath()
            guard rootURL.path.hasPrefix(temporaryDirectoryURL.path + "/") else {
                throw UITestingConfigurationError.unsafeDataRoot
            }

            let podPinFixtureAudioURL = try resolvePodPinFixtureAudioURL(
                environment: environment,
                dataRootURL: rootURL
            )

            do {
                try FileManager.default.createDirectory(
                    at: rootURL,
                    withIntermediateDirectories: true
                )
            } catch {
                throw UITestingConfigurationError.unusableDataRoot
            }

            let suiteComponent = rootURL.lastPathComponent
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }
                .joined(separator: "-")
            guard !suiteComponent.isEmpty,
                let podPinPreferences = UserDefaults(
                    suiteName: "com.cmy.OneBox.UITests.\(suiteComponent).PodPin"
                ),
                let stockWatchPreferences = UserDefaults(
                    suiteName: "com.cmy.OneBox.UITests.\(suiteComponent).StockWatch"
                )
            else {
                throw UITestingConfigurationError.unusablePreferences
            }

            return UITestingConfiguration(
                applicationSupportDirectoryURL: rootURL,
                podPinFixtureAudioURL: podPinFixtureAudioURL,
                podPinPreferences: podPinPreferences,
                stockWatchPreferences: stockWatchPreferences
            )
        }

        private static func resolvePodPinFixtureAudioURL(
            environment: [String: String],
            dataRootURL: URL
        ) throws -> URL? {
            guard let path = environment[podPinFixtureAudioEnvironmentKey], !path.isEmpty else {
                return nil
            }
            guard NSString(string: path).isAbsolutePath else {
                throw UITestingConfigurationError.unsafePodPinFixtureAudio
            }

            let fixtureURL = URL(fileURLWithPath: path, isDirectory: false)
                .standardizedFileURL
                .resolvingSymlinksInPath()
            guard fixtureURL.path.hasPrefix(dataRootURL.path + "/") else {
                throw UITestingConfigurationError.unsafePodPinFixtureAudio
            }
            let values: URLResourceValues
            do {
                values = try fixtureURL.resourceValues(forKeys: [.isRegularFileKey])
            } catch {
                throw UITestingConfigurationError.unusablePodPinFixtureAudio
            }
            guard values.isRegularFile == true else {
                throw UITestingConfigurationError.unusablePodPinFixtureAudio
            }
            return fixtureURL
        }
    }

    enum UITestingConfigurationError: Error, Equatable {
        case missingAbsoluteDataRoot
        case unsafeDataRoot
        case unusableDataRoot
        case unusablePreferences
        case unsafePodPinFixtureAudio
        case unusablePodPinFixtureAudio
    }
}
