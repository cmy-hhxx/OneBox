import CoreGraphics

public enum DesignMetrics {
    public static let windowAspectRatio = CGSize(width: 1048, height: 648)
    public static let defaultWindowSize = windowAspectRatio
    public static let minimumWindowSize = CGSize(
        width: 556 * windowAspectRatio.width / windowAspectRatio.height,
        height: 556
    )

    public static let space4: CGFloat = 4
    public static let space8: CGFloat = 8
    public static let space12: CGFloat = 12
    public static let space16: CGFloat = 16
    public static let space24: CGFloat = 24
    public static let space32: CGFloat = 32
    public static let space48: CGFloat = 48

    public static let mainInset: CGFloat = 24
    public static let sidebarWidth: CGFloat = 224
    public static let sidebarEdgeInset: CGFloat = 12
    public static let sidebarTextInset: CGFloat = 8
    public static let sidebarRowHeight: CGFloat = 36
    public static let brandMarkSize: CGFloat = 24
    public static let titlebarControlSize: CGFloat = 32
    public static let collapsedToggleLeadingInset: CGFloat = 80
    public static let dataRowHeight: CGFloat = 56
    public static let inspectorWidth: CGFloat = 248
    public static let cornerRadius: CGFloat = 8
}
