import CoreGraphics

struct AsciiRenderSnapshot: Sendable {
    let settings: AsciiSettings
    let transform: CanvasTransform
    let sourceSize: CGSize

    var outputSize: CGSize { settings.canvasPreset.outputSize }
    var glyphs: String { settings.characters.glyphs }
}
