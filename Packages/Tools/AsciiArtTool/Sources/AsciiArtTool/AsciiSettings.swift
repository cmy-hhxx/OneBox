struct AsciiSettings: Equatable, Sendable {
    var canvasPreset: AsciiCanvasPreset = .square
    var characters = AsciiCharacterState()
    var palettePreset: AsciiPalettePreset = .oneBox
    var characterSize: Double = 8 {
        didSet { characterSize = characterSize.clamped(to: 5...20) }
    }
    var density: Double = 0.6 {
        didSet { density = density.clamped(to: 0...1) }
    }
    var contrast: Double = 0.85 {
        didSet { contrast = contrast.clamped(to: 0.4...2) }
    }
    var isInverted = false
    var animation: AsciiAnimation = .wave
    var animationStrength: Double = 0.18 {
        didSet { animationStrength = animationStrength.clamped(to: 0...1) }
    }
    var hasTransparentBackground = false
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
