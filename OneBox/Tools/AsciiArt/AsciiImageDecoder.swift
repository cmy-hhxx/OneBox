import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

nonisolated enum AsciiImageDecoder {
    static let maximumFileSize = 50 * 1024 * 1024
    static let maximumPixelDimension = 4096
    private static let supportedExtensions = ["png", "jpg", "jpeg", "jpe", "svg"]
    private static let supportedRasterTypes = [UTType.png.identifier, UTType.jpeg.identifier]

    @concurrent
    static func decode(_ url: URL) async throws -> DecodedAsciiImage {
        try Task.checkCancellation()
        guard supportedExtensions.contains(url.pathExtension.lowercased()) else {
            throw AsciiToolError.unsupportedFormat
        }

        let isAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if isAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            if let fileSize = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                fileSize > maximumFileSize
            {
                throw AsciiToolError.fileTooLarge
            }

            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            guard data.count <= maximumFileSize else {
                throw AsciiToolError.fileTooLarge
            }
            try Task.checkCancellation()

            let image =
                if url.pathExtension.lowercased() == "svg" {
                    try decodeSVG(data)
                } else {
                    try decodeRaster(data)
                }
            try Task.checkCancellation()
            return DecodedAsciiImage(cgImage: image)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as AsciiToolError {
            throw error
        } catch {
            throw AsciiToolError.decodeFailed
        }
    }

    private static func decodeRaster(_ data: Data) throws -> CGImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw AsciiToolError.decodeFailed
        }
        guard let sourceType = CGImageSourceGetType(source) as String? else {
            throw AsciiToolError.decodeFailed
        }
        guard supportedRasterTypes.contains(sourceType) else {
            throw AsciiToolError.unsupportedFormat
        }
        guard CGImageSourceGetCount(source) == 1 else {
            throw AsciiToolError.unsupportedFormat
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelDimension,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else {
            throw AsciiToolError.decodeFailed
        }
        return image
    }

    private static func decodeSVG(_ data: Data) throws -> CGImage {
        guard let image = NSImage(data: data) else {
            throw AsciiToolError.decodeFailed
        }
        let sourceSize = image.size
        guard sourceSize.width.isFinite, sourceSize.height.isFinite,
            sourceSize.width > 0, sourceSize.height > 0
        else {
            throw AsciiToolError.decodeFailed
        }

        let longestEdge = max(sourceSize.width, sourceSize.height)
        let scale = min(1, Double(maximumPixelDimension) / longestEdge)
        var proposedRect = CGRect(
            origin: .zero,
            size: CGSize(
                width: max(1, sourceSize.width * scale),
                height: max(1, sourceSize.height * scale)
            )
        )
        guard let source = image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil)
        else {
            throw AsciiToolError.decodeFailed
        }
        return try downsampleIfNeeded(source)
    }

    private static func downsampleIfNeeded(_ image: CGImage) throws -> CGImage {
        let longestEdge = max(image.width, image.height)
        guard longestEdge > maximumPixelDimension else { return image }

        let scale = Double(maximumPixelDimension) / Double(longestEdge)
        let width = max(1, Int(Double(image.width) * scale))
        let height = max(1, Int(Double(image.height) * scale))
        guard
            let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else {
            throw AsciiToolError.decodeFailed
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let result = context.makeImage() else {
            throw AsciiToolError.decodeFailed
        }
        return result
    }
}
