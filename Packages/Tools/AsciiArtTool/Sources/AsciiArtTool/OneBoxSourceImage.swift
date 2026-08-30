import Foundation
import ImageIO

@MainActor
enum OneBoxSourceImage {
    static func make() throws -> CGImage {
        guard
            let url = Bundle.module.url(
                forResource: "onebox-mark-light",
                withExtension: "png"
            ),
            let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            throw AsciiToolError.decodeFailed
        }
        return image
    }
}
