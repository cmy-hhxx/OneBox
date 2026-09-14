import SwiftUI

public struct OpenToolDiagnosticsAction: Sendable {
    private let action: @MainActor @Sendable () -> Void

    public init(action: @escaping @MainActor @Sendable () -> Void = {}) {
        self.action = action
    }

    @MainActor public func callAsFunction() { action() }
}

private struct OpenToolDiagnosticsKey: EnvironmentKey {
    static let defaultValue = OpenToolDiagnosticsAction()
}

extension EnvironmentValues {
    public var openToolDiagnostics: OpenToolDiagnosticsAction {
        get { self[OpenToolDiagnosticsKey.self] }
        set { self[OpenToolDiagnosticsKey.self] = newValue }
    }
}
