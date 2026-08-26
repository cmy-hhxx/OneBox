import CoreGraphics

enum AsciiRenderGeometry {
    static func gridSize(outputSize: CGSize, characterSize: Double) -> AsciiGridSize {
        AsciiGridSize(
            columns: max(1, Int(outputSize.width / characterSize)),
            rows: max(1, Int(outputSize.height / characterSize))
        )
    }
}
