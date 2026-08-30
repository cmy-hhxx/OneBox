enum AsciiAnimation: String, CaseIterable, Identifiable, Sendable {
    case off = "关闭"
    case rain = "雨流"
    case wave = "波浪"
    case scanline = "扫描线"

    var id: Self { self }

    var shaderValue: Float {
        switch self {
        case .off: 0
        case .rain: 1
        case .wave: 2
        case .scanline: 3
        }
    }
}
