import OneBoxRuntime

@MainActor
public enum StockWatchModule {
    public static let id = ToolID(rawValue: "stock-watch")

    public static func makeRegistration(
        platform: any StockWatchPlatformClient
    ) -> ToolRegistration {
        let lifecycleCoordinator = StockWatchLifecycleCoordinator()
        return ToolRegistration(
            id: id,
            displayName: "股票看盘"
        ) {
            StockWatchView(
                platform: platform,
                lifecycleCoordinator: lifecycleCoordinator
            )
        }
    }
}
