import Testing

@testable import AsciiArtTool

@Suite("ASCII settings")
struct AsciiSettingsTests {
    @Test
    func `new settings default to static rendering`() {
        #expect(AsciiSettings().animation == .off)
    }

    @Test
    func `domain exposes the seven locked palettes`() {
        #expect(
            AsciiPalettePreset.allCases.map(\.rawValue) == [
                "OneBox", "Paper", "Inverse", "Cobalt", "Prism", "Terminal", "Signal",
            ])
    }

    @Test
    func `settings clamp values to the supported ranges`() {
        var settings = AsciiSettings()

        settings.characterSize = 2
        settings.density = 2
        settings.contrast = 0.1
        settings.animationStrength = 3

        #expect(settings.characterSize == 5)
        #expect(settings.density == 1)
        #expect(settings.contrast == 0.4)
        #expect(settings.animationStrength == 1)
    }

    @Test
    func `grid is derived from export size rather than preview size`() {
        let grid = AsciiRenderGeometry.gridSize(
            outputSize: AsciiCanvasPreset.landscape.outputSize,
            characterSize: 10
        )

        #expect(grid.columns == 192)
        #expect(grid.rows == 108)
    }
}
