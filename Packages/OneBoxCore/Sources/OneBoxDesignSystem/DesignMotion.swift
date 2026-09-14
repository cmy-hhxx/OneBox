import SwiftUI

/// BoardUI's shipped CSS timings. Its current button code supersedes older skill prose.
public enum DesignMotion {
    public static let hover = Animation.timingCurve(0.25, 0.1, 0.25, 1, duration: 0.15)
    public static let selection = Animation.timingCurve(0.4, 0, 0.2, 1, duration: 0.2)
    public static let sidebar = Animation.timingCurve(0.4, 0, 0.2, 1, duration: 0.3)
    public static let panel = Animation.timingCurve(0.32, 0.72, 0, 1, duration: 0.3)
    public static let notification = Animation.interpolatingSpring(
        mass: 0.7, stiffness: 520, damping: 42)
    public static func press(_ isPressed: Bool) -> Animation {
        .timingCurve(0.4, 0, 0.2, 1, duration: isPressed ? 0.22 : 0.42)
    }
}
