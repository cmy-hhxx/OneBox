import OSLog

@MainActor
final class AsciiFirstContentPerformanceTrace {
    private static let signposter = OSSignposter(
        subsystem: "com.cmy.OneBox",
        category: "ASCII"
    )

    private var interval: OSSignpostIntervalState?

    func begin() {
        cancel()
        interval = Self.signposter.beginInterval("FirstContentReady")
    }

    @discardableResult
    func finish() -> Bool {
        guard let interval else { return false }
        self.interval = nil
        Self.signposter.endInterval("FirstContentReady", interval)
        return true
    }

    func cancel() {
        guard let interval else { return }
        self.interval = nil
        Self.signposter.endInterval(
            "FirstContentReady",
            interval,
            "cancelled"
        )
    }
}
