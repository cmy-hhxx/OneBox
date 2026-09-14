import SwiftUI

enum LightPaletteHex {
    static let background: UInt32 = 0xFFFFFF
    static let sidebar: UInt32 = 0xF7F7F7
    static let surface: UInt32 = 0xFFFFFF
    static let surfaceElevated: UInt32 = 0xF7F7F7
    static let selection: UInt32 = 0xF7F7F7
    static let border: UInt32 = 0xEBEBEB
    static let textPrimary: UInt32 = 0x0A0A0A
    static let textSecondary: UInt32 = 0x737373
    static let accent: UInt32 = 0x2B7FFF
    static let accentPressed: UInt32 = 0x155DFC
    static let textOnAccent: UInt32 = 0xFFFFFF
    static let warningSurface: UInt32 = 0xFFF4DB
    static let negativeSurface: UInt32 = 0xFDECEB
    static let primaryGradientStart: UInt32 = 0x2B7FFF
    static let primaryGradientEnd: UInt32 = 0x155DFC
    static let toggleTrack: UInt32 = 0xEBEBEB
    static let textDisabled: UInt32 = 0xA1A1A1
    static let accentHover: UInt32 = 0x3392FF
    static let accentDeep: UInt32 = 0x1447E6
    static let borderHover: UInt32 = 0xD4D4D4
    static let borderActive: UInt32 = 0xA1A1A1
    static let sliderTrack: UInt32 = 0xEBEBEB
    static let sliderTrackHover: UInt32 = 0xD4D4D4
    static let switchChipStart: UInt32 = 0x2473FE
    static let switchChipEnd: UInt32 = 0x0450E2
    static let brandMarkHost: UInt32 = 0x3569CE
    static let brandMarkCore: UInt32 = 0xFFF1D6
    static let brandGradientStart: UInt32 = 0x3B6FD8
    static let brandGradientMiddle: UInt32 = 0x8A5CBF
    static let brandGradientEnd: UInt32 = 0xBC4535
    static let positive: UInt32 = 0x08754A
    static let negative: UInt32 = 0xB42318
    static let warning: UInt32 = 0x865D00
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
    public let accentPressed: Color
    public let textOnAccent: Color
    public let warningSurface: Color
    public let negativeSurface: Color
    public let primaryGradientStart: Color
    public let primaryGradientEnd: Color
    public let toggleTrack: Color
    public let textDisabled: Color
    public let controlShadow: Color
    public let controlHighlight: Color
    public let focusRing: Color
    public let accentHover: Color
    public let accentDeep: Color
    public let borderHover: Color
    public let borderActive: Color
    public let sliderTrack: Color
    public let sliderTrackHover: Color
    public let switchChipStart: Color
    public let switchChipEnd: Color
    public let sliderInsetShadow: Color
    public let sliderFillShadow: Color
    public let sliderThumbShadow: Color
    public let sliderThumbHighlight: Color
    public let sliderDragShadow: Color
    public let dropdownContactShadow: Color
    public let dropdownAmbientShadow: Color
    public let sidebarShadow: Color
    public let sidebarOutline: Color
    public let controlIndicator: Color
    public let controlIndicatorSubtle: Color
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
        accentPressed: Color(hex: LightPaletteHex.accentPressed),
        textOnAccent: Color(hex: LightPaletteHex.textOnAccent),
        warningSurface: Color(hex: LightPaletteHex.warningSurface),
        negativeSurface: Color(hex: LightPaletteHex.negativeSurface),
        primaryGradientStart: Color(hex: LightPaletteHex.primaryGradientStart),
        primaryGradientEnd: Color(hex: LightPaletteHex.primaryGradientEnd),
        toggleTrack: Color(hex: LightPaletteHex.toggleTrack),
        textDisabled: Color(hex: LightPaletteHex.textDisabled),
        controlShadow: Color.black.opacity(0.05),
        controlHighlight: Color.white.opacity(0.25),
        focusRing: Color(hex: LightPaletteHex.accent).opacity(0.14),
        accentHover: Color(hex: LightPaletteHex.accentHover),
        accentDeep: Color(hex: LightPaletteHex.accentDeep),
        borderHover: Color(hex: LightPaletteHex.borderHover),
        borderActive: Color(hex: LightPaletteHex.borderActive),
        sliderTrack: Color(hex: LightPaletteHex.sliderTrack),
        sliderTrackHover: Color(hex: LightPaletteHex.sliderTrackHover),
        switchChipStart: Color(hex: LightPaletteHex.switchChipStart),
        switchChipEnd: Color(hex: LightPaletteHex.switchChipEnd),
        sliderInsetShadow: Color.black.opacity(0.06),
        sliderFillShadow: Color(hex: LightPaletteHex.accentPressed).opacity(0.16),
        sliderThumbShadow: Color.black.opacity(0.1),
        sliderThumbHighlight: Color.white.opacity(0.8),
        sliderDragShadow: Color(hex: LightPaletteHex.accentPressed).opacity(0.22),
        dropdownContactShadow: Color.black.opacity(0.04),
        dropdownAmbientShadow: Color.black.opacity(0.02),
        sidebarShadow: Color.black.opacity(0.06),
        sidebarOutline: Color.black.opacity(0.32),
        controlIndicator: Color.white,
        controlIndicatorSubtle: Color(hex: 0xF7F7F7),
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
        accent: Color(hex: 0x88ABFF),
        accentPressed: Color(hex: 0xA5BFFF),
        textOnAccent: Color(hex: 0x152443),
        warningSurface: Color(hex: 0x352D1A),
        negativeSurface: Color(hex: 0x391E24),
        primaryGradientStart: Color(hex: 0xAB98FF),
        primaryGradientEnd: Color(hex: 0x83A6FF),
        toggleTrack: Color(hex: 0x414957),
        textDisabled: Color(hex: 0x727D90),
        controlShadow: Color.black.opacity(0.3),
        controlHighlight: Color.white.opacity(0.18),
        focusRing: Color(hex: 0x88ABFF).opacity(0.2),
        accentHover: Color(hex: 0x8EC5FF),
        accentDeep: Color(hex: 0x2B7FFF),
        borderHover: Color(hex: 0x525252),
        borderActive: Color(hex: 0x737373),
        sliderTrack: Color(hex: 0x404040),
        sliderTrackHover: Color(hex: 0x525252),
        switchChipStart: Color(hex: 0x2473FE),
        switchChipEnd: Color(hex: 0x0450E2),
        sliderInsetShadow: Color.black.opacity(0.2),
        sliderFillShadow: Color(hex: 0x155DFC).opacity(0.16),
        sliderThumbShadow: Color.black.opacity(0.2),
        sliderThumbHighlight: Color.white.opacity(0.8),
        sliderDragShadow: Color(hex: 0x155DFC).opacity(0.22),
        dropdownContactShadow: Color.black.opacity(0.15),
        dropdownAmbientShadow: Color.black.opacity(0.1),
        sidebarShadow: Color.black.opacity(0.3),
        sidebarOutline: Color.black.opacity(0.45),
        controlIndicator: Color.white,
        controlIndicatorSubtle: Color(hex: 0xF7F7F7),
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
