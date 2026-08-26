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
            StockWatchModule.registration,
            BlogListenModule.registration,
            WindowFocusModule.registration,
        ])
    }
}
