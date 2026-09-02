import CoreGraphics
import Foundation
import SwiftUI

private struct ArtworkRGBA: Sendable {
    let red: Double
    let green: Double
    let blue: Double

    var artworkAccentColor: Color {
        Color(red: red, green: green, blue: blue)
    }
}

@MainActor
final class ArtworkColorModel: ObservableObject {
    @Published private(set) var color: Color?

    private var task: Task<Void, Never>?
    private let timeoutTaskOwner = CooperativeTaskOwner()
    private static let cache = NSCache<NSURL, ArtworkColorBox>()

    func load(from url: URL?) {
        task?.cancel()
        guard let url else {
            color = nil
            return
        }
        if let cached = Self.cache.object(forKey: url as NSURL) {
            color = cached.value.artworkAccentColor
            return
        }
        let timeoutTaskOwner = timeoutTaskOwner
        task = Task { [weak self] in
            let result = await withCooperativeTimeout(
                .seconds(2),
                owner: timeoutTaskOwner
            ) {
                await ArtworkColorExtractor.sample(at: url)
            }
            guard !Task.isCancelled, case .value(let sample?) = result else { return }
            Self.cache.setObject(ArtworkColorBox(sample), forKey: url as NSURL)
            self?.color = sample.artworkAccentColor
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        timeoutTaskOwner.cancelAll()
    }

    deinit {
        task?.cancel()
        timeoutTaskOwner.cancelAll()
    }
}

private final class ArtworkColorBox: @unchecked Sendable {
    let value: ArtworkRGBA

    init(_ value: ArtworkRGBA) { self.value = value }
}

private enum ArtworkColorExtractor {
    nonisolated static func sample(at url: URL) async -> ArtworkRGBA? {
        guard !Task.isCancelled else { return nil }
        guard
            let image = await ArtworkImageDecoder.thumbnail(
                at: url,
                maxPixelSize: 48
            )
        else { return nil }

        let sampleWidth = 24
        let sampleHeight = 24
        let bytesPerRow = sampleWidth * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * sampleHeight)
        guard
            let context = CGContext(
                data: &pixels,
                width: sampleWidth,
                height: sampleHeight,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else { return nil }
        context.interpolationQuality = .medium
        context.draw(
            image,
            in: CGRect(x: 0, y: 0, width: sampleWidth, height: sampleHeight)
        )

        var weightedRed = 0.0
        var weightedGreen = 0.0
        var weightedBlue = 0.0
        var totalWeight = 0.0

        for offset in stride(from: 0, to: pixels.count, by: 4) {
            let alpha = Double(pixels[offset + 3]) / 255
            guard alpha > 0.2 else { continue }

            let red = min(Double(pixels[offset]) / 255 / alpha, 1)
            let green = min(Double(pixels[offset + 1]) / 255 / alpha, 1)
            let blue = min(Double(pixels[offset + 2]) / 255 / alpha, 1)
            let maximum = max(red, max(green, blue))
            let minimum = min(red, min(green, blue))
            let chroma = maximum - minimum
            let saturation = maximum > 0 ? chroma / maximum : 0
            let luminance = red * 0.2126 + green * 0.7152 + blue * 0.0722

            // Near-white or near-black pixels are usually sleeve backgrounds
            // and shadows. Weight distinctive colors so a small logo can drive
            // the stage color instead of being washed out by a white cover.
            guard luminance > 0.08, luminance < 0.92, saturation > 0.12 else { continue }
            let weight = alpha * saturation * saturation * (0.5 + chroma)
            weightedRed += red * weight
            weightedGreen += green * weight
            weightedBlue += blue * weight
            totalWeight += weight
        }

        guard !Task.isCancelled else { return nil }
        guard totalWeight > 0 else {
            return averageColor(from: pixels)
        }

        return ArtworkRGBA(
            red: weightedRed / totalWeight,
            green: weightedGreen / totalWeight,
            blue: weightedBlue / totalWeight
        )
    }

    private static func averageColor(from pixels: [UInt8]) -> ArtworkRGBA? {
        var red = 0.0
        var green = 0.0
        var blue = 0.0
        var count = 0.0

        for offset in stride(from: 0, to: pixels.count, by: 4) {
            let alpha = Double(pixels[offset + 3]) / 255
            guard alpha > 0.2 else { continue }
            red += min(Double(pixels[offset]) / 255 / alpha, 1)
            green += min(Double(pixels[offset + 1]) / 255 / alpha, 1)
            blue += min(Double(pixels[offset + 2]) / 255 / alpha, 1)
            count += 1
        }

        guard count > 0 else { return nil }
        return ArtworkRGBA(red: red / count, green: green / count, blue: blue / count)
    }
}
