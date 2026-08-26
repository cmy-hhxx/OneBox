import CoreText

@MainActor
enum OneBoxSourceImage {
    static func make() throws -> CGImage {
        let size = 1024
        guard
            let context = CGContext(
                data: nil,
                width: size,
                height: size,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else {
            throw AsciiToolError.decodeFailed
        }

        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))
        drawOne(in: context)

        guard let image = context.makeImage() else {
            throw AsciiToolError.decodeFailed
        }
        return image
    }

    private static func drawOne(in context: CGContext) {
        let font = CTFontCreateWithName("SFMono-Bold" as CFString, 660, nil)
        var character = UniChar(49)
        var glyph = CGGlyph()
        guard CTFontGetGlyphsForCharacters(font, &character, &glyph, 1),
            let glyphPath = CTFontCreatePathForGlyph(font, glyph, nil)
        else { return }

        let bounds = glyphPath.boundingBox
        var transform = CGAffineTransform(
            translationX: 512 - bounds.midX,
            y: 236 - bounds.minY
        )
        guard let positionedPath = glyphPath.copy(using: &transform) else { return }

        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.addPath(positionedPath)
        context.fillPath()
    }
}
