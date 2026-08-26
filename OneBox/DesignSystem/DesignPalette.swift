import SwiftUI

enum LightPaletteHex {
    static let background: UInt32 = 0xFBFBFA
    static let sidebar: UInt32 = 0xF0F0EE
    static let surface: UInt32 = 0xFFFFFF
    static let surfaceElevated: UInt32 = 0xEEEEEC
    static let selection: UInt32 = 0xE4E4E2
    static let border: UInt32 = 0xD8D8D5
    static let textPrimary: UInt32 = 0x1B1C1E
    static let textSecondary: UInt32 = 0x66676A
    static let accent: UInt32 = 0xBC4535
    static let brandMarkHost: UInt32 = 0x3569CE
    static let brandMarkCore: UInt32 = 0xFFF1D6
    static let brandGradientStart: UInt32 = 0x3B6FD8
    static let brandGradientMiddle: UInt32 = 0x8A5CBF
    static let brandGradientEnd: UInt32 = 0xBC4535
    static let positive: UInt32 = 0x087A4B
    static let negative: UInt32 = 0xB42318
    static let warning: UInt32 = 0x8F6400
    static let info: UInt32 = 0x1C587B
    static let infoSurface: UInt32 = 0xE8F3F9
}

public struct DesignPalette: Sendable {
    public let background: Color
    public let sidebar: Color
    public let surface: Color
    public let surfaceElevated: Color
    public let selection: Color
    public let border: Color
    public let textPrimary: Color
    public let textSecondary: Color
    public let accent: Color
    public let brandMarkHost: Color
    public let brandMarkCore: Color
    public let brandGradientStart: Color
    public let brandGradientMiddle: Color
    public let brandGradientEnd: Color
    public let positive: Color
    public let negative: Color
    public let warning: Color
    public let info: Color
    public let infoSurface: Color

    public static let light = DesignPalette(
        background: Color(hex: LightPaletteHex.background),
        sidebar: Color(hex: LightPaletteHex.sidebar),
        surface: Color(hex: LightPaletteHex.surface),
        surfaceElevated: Color(hex: LightPaletteHex.surfaceElevated),
        selection: Color(hex: LightPaletteHex.selection),
        border: Color(hex: LightPaletteHex.border),
        textPrimary: Color(hex: LightPaletteHex.textPrimary),
        textSecondary: Color(hex: LightPaletteHex.textSecondary),
        accent: Color(hex: LightPaletteHex.accent),
        brandMarkHost: Color(hex: LightPaletteHex.brandMarkHost),
        brandMarkCore: Color(hex: LightPaletteHex.brandMarkCore),
        brandGradientStart: Color(hex: LightPaletteHex.brandGradientStart),
        brandGradientMiddle: Color(hex: LightPaletteHex.brandGradientMiddle),
        brandGradientEnd: Color(hex: LightPaletteHex.brandGradientEnd),
        positive: Color(hex: LightPaletteHex.positive),
        negative: Color(hex: LightPaletteHex.negative),
        warning: Color(hex: LightPaletteHex.warning),
        info: Color(hex: LightPaletteHex.info),
        infoSurface: Color(hex: LightPaletteHex.infoSurface)
    )

    public static let dark = DesignPalette(
        background: Color(hex: 0x07080A),
        sidebar: Color(hex: 0x0D0D0D),
        surface: Color(hex: 0x0D0D0D),
        surfaceElevated: Color(hex: 0x18191A),
        selection: Color(hex: 0x191A1C),
        border: Color(hex: 0x242728),
        textPrimary: Color(hex: 0xF4F4F6),
        textSecondary: Color(hex: 0x9C9C9D),
        accent: Color(hex: 0xFF6161),
        brandMarkHost: Color(hex: 0x5E82D8),
        brandMarkCore: Color(hex: 0xE8DBC4),
        brandGradientStart: Color(hex: 0x6EA8FE),
        brandGradientMiddle: Color(hex: 0xB197FC),
        brandGradientEnd: Color(hex: 0xFF8787),
        positive: Color(hex: 0x59D499),
        negative: Color(hex: 0xFF6161),
        warning: Color(hex: 0xFFC533),
        info: Color(hex: 0xCDCDCD),
        infoSurface: Color(hex: 0x10222E)
    )

    public static func resolve(_ colorScheme: ColorScheme) -> DesignPalette {
        colorScheme == .dark ? .dark : .light
    }
}

extension Color {
    fileprivate init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
