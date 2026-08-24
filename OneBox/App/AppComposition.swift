import BlogListenTool
import OneBoxRuntime
import StockWatchTool
import WindowFocusTool

enum AppComposition {
    static func makeCatalog() -> ToolCatalog {
        ToolCatalog(registrations: [
            StockWatchModule.registration,
            BlogListenModule.registration,
            WindowFocusModule.registration,
        ])
    }
}
