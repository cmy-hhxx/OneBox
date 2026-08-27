import Foundation
import ImageIO

@MainActor
enum OneBoxSourceImage {
    private final class BundleToken {}

    static func make() throws -> CGImage {
        let bundles = [Bundle(for: BundleToken.self), Bundle.main]
        for bundle in bundles {
            guard
                let url = bundle.url(
                    forResource: "onebox-mark-light",
                    withExtension: "png"
                ),
                let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
            else { continue }
            return image
        }
        throw AsciiToolError.decodeFailed
    }
}
