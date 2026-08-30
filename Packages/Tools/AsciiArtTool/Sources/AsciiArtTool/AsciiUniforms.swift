import simd

struct AsciiUniforms {
    var darkColor: SIMD4<Float>
    var middleColor: SIMD4<Float>
    var lightColor: SIMD4<Float>
    var backgroundColor: SIMD4<Float>
    var transform: SIMD4<Float>
    var geometry: SIMD4<Float>
    var settings: SIMD4<Float>
    var animation: SIMD4<Float>

    init(snapshot: AsciiRenderSnapshot, time: Float, glyphCount: Int) {
        let palette = snapshot.settings.palettePreset.palette
        let grid = AsciiRenderGeometry.gridSize(
            outputSize: snapshot.outputSize,
            characterSize: snapshot.settings.characterSize
        )
        darkColor = palette.dark.vector
        middleColor = palette.middle.vector
        lightColor = palette.light.vector
        backgroundColor = palette.background.vector
        transform = SIMD4(
            Float(snapshot.transform.scale),
            Float(snapshot.transform.offset.x),
            Float(snapshot.transform.offset.y),
            0
        )
        geometry = SIMD4(
            Float(grid.columns),
            Float(grid.rows),
            Float(snapshot.sourceSize.width / max(snapshot.sourceSize.height, 1)),
            Float(snapshot.outputSize.width / max(snapshot.outputSize.height, 1))
        )
        settings = SIMD4(
            Float(snapshot.settings.density),
            Float(snapshot.settings.contrast),
            snapshot.settings.isInverted ? 1 : 0,
            snapshot.settings.animation.shaderValue
        )
        animation = SIMD4(
            time,
            Float(snapshot.settings.animationStrength),
            Float(max(glyphCount, 1)),
            snapshot.settings.hasTransparentBackground ? 1 : 0
        )
    }
}
