enum AsciiPalettePreset: String, CaseIterable, Identifiable, Sendable {
    case oneBox = "OneBox"
    case paper = "Paper"
    case inverse = "Inverse"
    case cobalt = "Cobalt"
    case prism = "Prism"
    case terminal = "Terminal"
    case signal = "Signal"

    var id: Self { self }

    var palette: AsciiPalette {
        switch self {
        case .oneBox:
            AsciiPalette(
                dark: AsciiColor(hex: 0x3B6FD8),
                middle: AsciiColor(hex: 0x8A5CBF),
                light: AsciiColor(hex: 0xBC4535),
                background: AsciiColor(hex: 0xFBFBFA)
            )
        case .paper:
            AsciiPalette(
                dark: AsciiColor(hex: 0x050505),
                middle: AsciiColor(hex: 0x3F3F3F),
                light: AsciiColor(hex: 0x858585),
                background: AsciiColor(hex: 0xFFFFFF)
            )
        case .inverse:
            AsciiPalette(
                dark: AsciiColor(hex: 0xFFFFFF),
                middle: AsciiColor(hex: 0xD7D7D7),
                light: AsciiColor(hex: 0x8F8F8F),
                background: AsciiColor(hex: 0x000000)
            )
        case .cobalt:
            AsciiPalette(
                dark: AsciiColor(hex: 0xFFFFFF),
                middle: AsciiColor(hex: 0xDBE7FF),
                light: AsciiColor(hex: 0x8EAFFF),
                background: AsciiColor(hex: 0x1557FF)
            )
        case .prism:
            AsciiPalette(
                dark: AsciiColor(hex: 0x0B45C6),
                middle: AsciiColor(hex: 0x7A32D5),
                light: AsciiColor(hex: 0xE02578),
                background: AsciiColor(hex: 0xFFFFFF)
            )
        case .terminal:
            AsciiPalette(
                dark: AsciiColor(hex: 0xD8FFD0),
                middle: AsciiColor(hex: 0x39FF14),
                light: AsciiColor(hex: 0x078F32),
                background: AsciiColor(hex: 0x000000)
            )
        case .signal:
            AsciiPalette(
                dark: AsciiColor(hex: 0xFFFFFF),
                middle: AsciiColor(hex: 0xFFD2D4),
                light: AsciiColor(hex: 0xFF8D92),
                background: AsciiColor(hex: 0xE5252A)
            )
        }
    }
}
