import SwiftUI

/// A measurement-only signal from tool content to the host. Reporting readiness
/// does not activate, suspend, or otherwise control a tool's business lifecycle.
public struct ToolContentReadinessReporter: Sendable {
    private let report: @MainActor @Sendable () -> Void

    public init(
        report: @escaping @MainActor @Sendable () -> Void = {}
    ) {
        self.report = report
    }

    @MainActor
    public func reportFirstContentReady() {
        report()
    }
}

private struct ToolContentReadinessReporterKey: EnvironmentKey {
    static let defaultValue = ToolContentReadinessReporter()
}

extension EnvironmentValues {
    public var toolContentReadinessReporter: ToolContentReadinessReporter {
        get { self[ToolContentReadinessReporterKey.self] }
        set { self[ToolContentReadinessReporterKey.self] = newValue }
    }
}
