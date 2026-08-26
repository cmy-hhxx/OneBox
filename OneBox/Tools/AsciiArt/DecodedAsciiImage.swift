import CoreGraphics

struct DecodedAsciiImage: Sendable {
    let cgImage: CGImage
    let sourceName: String
}
