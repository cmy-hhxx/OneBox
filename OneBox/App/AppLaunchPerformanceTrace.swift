import OSLog

@MainActor
final class AppLaunchPerformanceTrace {
    private static let signposter = OSSignposter(
        subsystem: "com.cmy.OneBox",
        category: "Host"
    )

    private var interval: OSSignpostIntervalState?

    init() {
        interval = Self.signposter.beginInterval("AppLaunchToInteractive")
    }

    func finish() {
        guard let interval else { return }
        self.interval = nil
        Self.signposter.endInterval("AppLaunchToInteractive", interval)
    }
}
