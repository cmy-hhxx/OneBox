import AsciiArtTool
import BlogListenTool
import OneBoxRuntime
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
            BlogListenModule.registration,
            WindowFocusModule.registration,
        ])
    }
}
