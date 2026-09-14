import CoreText
import SwiftUI

public enum DesignTypography {
    public static let pageTitle = font(24, weight: .medium)
    public static let sidebarTitle = font(18, weight: .medium)
    public static let sectionTitle = font(16, weight: .medium)
    public static let body = font(14, weight: .regular)
    public static let bodyMedium = font(14, weight: .medium)
    public static let metadata = font(12, weight: .regular)
    public static let compact = font(13, weight: .regular)
    public static let diagnostic = Font.system(size: 12, weight: .regular, design: .monospaced)
    public static let metric = font(20, weight: .medium)
    public static let artworkSymbol = Font.system(size: 48, weight: .light)

    private static let registeredInter: Bool = {
        guard let url = Bundle.module.url(forResource: "InterVariable", withExtension: "ttf") else {
            return false
        }
        return CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }()

    private static func font(_ size: CGFloat, weight: Font.Weight) -> Font {
        _ = registeredInter
        return Font.custom("InterVariable", size: size).weight(weight)
    }
}
