import CoreGraphics

struct AsciiSource: Sendable {
    let image: CGImage
    let name: String
    let isBuiltIn: Bool
}
