import CoreGraphics

enum AsciiCanvasPreset: String, CaseIterable, Identifiable, Sendable {
    case square = "1:1"
    case landscape = "16:9"
    case portrait = "9:16"

    var id: Self { self }

    var outputSize: CGSize {
        switch self {
        case .square:
            CGSize(width: 1024, height: 1024)
        case .landscape:
            CGSize(width: 1920, height: 1080)
        case .portrait:
            CGSize(width: 1080, height: 1920)
        }
    }
}
