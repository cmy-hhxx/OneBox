import AsciiArtTool
import OneBoxRuntime
import PodPinTool
import StockWatchTool

enum AppComposition {
    static func makeCatalog() -> ToolCatalog {
        let podPinPlatform = PodPinSystemPlatformAdapter()
        return ToolCatalog(registrations: [
            AsciiArtModule.makeRegistration(
                deviceProvider: SystemAsciiMetalDeviceProvider()
            ),
            StockWatchModule.makeRegistration(
                platform: MacStockWatchPlatformClient()
            ),
            PodPinModule.makeRegistration(
                platform: podPinPlatform,
                debugFixtureAudioURL: podPinPlatform.debugFixtureAudioURL,
                externalToolsDirectoryURL: podPinPlatform.externalToolsDirectoryURL
            ),
        ])
    }
}
