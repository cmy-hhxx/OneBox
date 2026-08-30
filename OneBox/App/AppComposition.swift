import AsciiArtTool
import OneBoxRuntime
import PodPinTool
import StockWatchTool
import WindowFocusTool

enum AppComposition {
    static func makeCatalog() -> ToolCatalog {
        ToolCatalog(registrations: [
            AsciiArtModule.makeRegistration(
                deviceProvider: SystemAsciiMetalDeviceProvider()
            ),
            StockWatchModule.makeRegistration(
                platform: MacStockWatchPlatformClient()
            ),
            PodPinModule.makeRegistration(
                platform: PodPinSystemPlatformAdapter()
            ),
            WindowFocusModule.registration,
        ])
    }
}
