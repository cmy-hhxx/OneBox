import OneBoxRuntime

public enum WindowFocusModule {
    public static let id = ToolID(rawValue: "window-focus")

    public static let registration = ToolRegistration(
        id: id,
        displayName: "窗口聚焦"
    ) { _ in
        WindowFocusView()
    }
}
