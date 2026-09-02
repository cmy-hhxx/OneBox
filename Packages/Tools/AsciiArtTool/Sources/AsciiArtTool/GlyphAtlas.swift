import CoreGraphics
import CoreText
import Foundation
import MetalKit

enum GlyphAtlas {
    static func makeTexture(glyphs: String, device: MTLDevice) throws -> MTLTexture {
        let characters = Array(glyphs)
        let cellSize = 64
        let pixelWidth = max(characters.count, 1) * cellSize
        guard
            let context = CGContext(
                data: nil,
                width: pixelWidth,
                height: cellSize,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else {
            throw AsciiToolError.metalUnavailable
        }

        context.clear(CGRect(x: 0, y: 0, width: pixelWidth, height: cellSize))
        context.textMatrix = .identity
        guard let font = CTFontCreateUIFontForLanguage(.userFixedPitch, 46, nil) else {
            throw AsciiToolError.metalUnavailable
        }
        let attributes: [CFString: Any] = [
            kCTFontAttributeName: font,
            kCTForegroundColorAttributeName: CGColor(gray: 1, alpha: 1),
        ]
        for (index, character) in characters.enumerated() {
            guard
                let attributedString = CFAttributedStringCreate(
                    nil,
                    String(character) as CFString,
                    attributes as CFDictionary
                )
            else {
                throw AsciiToolError.metalUnavailable
            }
            let line = CTLineCreateWithAttributedString(attributedString)
            var ascent: CGFloat = 0
            var descent: CGFloat = 0
            let width = CTLineGetTypographicBounds(line, &ascent, &descent, nil)
            context.textPosition = CGPoint(
                x: Double(index * cellSize) + (Double(cellSize) - width) / 2,
                y: (Double(cellSize) - ascent - descent) / 2 + descent
            )
            CTLineDraw(line, context)
        }

        guard let image = context.makeImage() else {
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
