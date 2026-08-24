import OneBoxRuntime

public enum StockWatchModule {
    public static let id = ToolID(rawValue: "stock-watch")

    public static let registration = ToolRegistration(
        id: id,
        displayName: "股票看盘"
    ) { _ in
        StockWatchView()
    }
}
