import simd

struct AsciiColor: Equatable, Sendable {
    let red: Float
    let green: Float
    let blue: Float
    let alpha: Float

    init(hex: UInt32, alpha: Float = 1) {
        red = Float((hex >> 16) & 0xFF) / 255
        green = Float((hex >> 8) & 0xFF) / 255
        blue = Float(hex & 0xFF) / 255
        self.alpha = alpha
    }

    var vector: SIMD4<Float> {
        SIMD4(red, green, blue, alpha)
    }
}
