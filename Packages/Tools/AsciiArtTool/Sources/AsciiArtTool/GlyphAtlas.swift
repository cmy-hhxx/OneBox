import AppKit
import MetalKit

@MainActor
enum GlyphAtlas {
    static func makeTexture(glyphs: String, device: MTLDevice) throws -> MTLTexture {
        let characters = Array(glyphs)
        let cellSize = 64
        let pixelWidth = max(characters.count, 1) * cellSize
        guard
            let bitmap = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: pixelWidth,
                pixelsHigh: cellSize,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            ),
            let context = NSGraphicsContext(bitmapImageRep: bitmap)
        else {
            throw AsciiToolError.metalUnavailable
        }

        bitmap.size = NSSize(width: pixelWidth, height: cellSize)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSColor.clear.setFill()
        NSRect(x: 0, y: 0, width: pixelWidth, height: cellSize).fill()

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 46, weight: .bold),
            .foregroundColor: NSColor.white,
        ]
        for (index, character) in characters.enumerated() {
            let string = String(character) as NSString
            let size = string.size(withAttributes: attributes)
            let rect = NSRect(
                x: Double(index * cellSize) + (Double(cellSize) - size.width) / 2,
                y: (Double(cellSize) - size.height) / 2,
                width: size.width,
                height: size.height
            )
            string.draw(in: rect, withAttributes: attributes)
        }
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        guard let image = bitmap.cgImage else {
            throw AsciiToolError.metalUnavailable
        }
        return try MTKTextureLoader(device: device).newTexture(
            cgImage: image,
            options: [
                .SRGB: false,
                .origin: MTKTextureLoader.Origin.topLeft,
            ]
        )
    }
}
