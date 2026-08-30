import CoreGraphics
import Testing

@testable import AsciiArtTool

@Suite("ASCII canvas presets")
struct AsciiCanvasPresetTests {
    @Test(arguments: [
        (AsciiCanvasPreset.square, CGSize(width: 1024, height: 1024)),
        (AsciiCanvasPreset.landscape, CGSize(width: 1920, height: 1080)),
        (AsciiCanvasPreset.portrait, CGSize(width: 1080, height: 1920)),
    ])
    func `preset resolves its locked export size`(
        preset: AsciiCanvasPreset,
        expectedSize: CGSize
    ) {
        #expect(preset.outputSize == expectedSize)
    }
}
