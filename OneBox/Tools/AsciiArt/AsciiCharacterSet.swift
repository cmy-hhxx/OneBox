enum AsciiCharacterSet: String, CaseIterable, Identifiable, Sendable {
    case classic = "Classic"
    case blocks = "Blocks"
    case binary = "Binary"
    case matrix = "Matrix"
    case minimal = "Minimal"
    case custom = "Custom"

    var id: Self { self }

    var glyphs: String {
        switch self {
        case .classic:
            " .,:;i1tfLCG08@"
        case .blocks:
            " ░▒▓█"
        case .binary:
            " 01"
        case .matrix:
            " ･:ﾊﾐﾋｰｳｼﾅﾓﾆｻﾜﾂｵﾘ"
        case .minimal:
            " ·+×#"
        case .custom:
            ""
        }
    }
}
