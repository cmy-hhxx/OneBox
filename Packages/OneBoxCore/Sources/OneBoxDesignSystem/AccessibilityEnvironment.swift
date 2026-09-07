import SwiftUI

extension EnvironmentValues {
    /// An isolated UI-test override for exercising the same Reduce Motion
    /// branches as the system preference without changing machine state.
    @Entry public var oneBoxAccessibilityReduceMotionOverride: Bool? = nil
}
