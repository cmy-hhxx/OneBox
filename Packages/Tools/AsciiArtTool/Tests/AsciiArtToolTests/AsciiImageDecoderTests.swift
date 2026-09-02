import CoreGraphics
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import AsciiArtTool

@Suite("ASCII image import")
struct AsciiImageDecoderTests {
    @Test
    func `png import preserves alpha`() async throws {
        let url = try temporaryURL(extension: "png")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try writeImage(to: url, type: .png, alpha: 0)

        let image = try await AsciiImageDecoder.decode(url)

        #expect(image.cgImage.width == 2)
        #expect(image.cgImage.height == 2)
        #expect(image.cgImage.alphaInfo != .none)
    }

    @Test
    func `svg import rasterizes into the supported image pipeline`() async throws {
        let url = try temporaryURL(extension: "svg")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let svg = """
            <svg xmlns="http://www.w3.org/2000/svg" width="120" height="80">
              <rect width="120" height="80" fill="#ffffff"/>
              <text x="60" y="62" text-anchor="middle" font-size="64">1</text>
            </svg>
            """
        try Data(svg.utf8).write(to: url)

        let image = try await AsciiImageDecoder.decode(url)

        #expect(image.cgImage.width > 0)
        #expect(Double(image.cgImage.width) / Double(image.cgImage.height) == 1.5)
    }

    @Test
    func `svg dimensions are bounded before rasterization`() async throws {
        let url = try temporaryURL(extension: "svg")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let svg = """
            <svg xmlns="http://www.w3.org/2000/svg" width="10000" height="5000">
              <rect width="100%" height="100%" fill="#000000"/>
            </svg>
            """
        try Data(svg.utf8).write(to: url)

        let image = try await AsciiImageDecoder.decode(url)

        #expect(image.cgImage.width == AsciiImageDecoder.maximumPixelDimension)
        #expect(image.cgImage.height == AsciiImageDecoder.maximumPixelDimension / 2)
    }

    @Test
    func `oversized dimensions are downsampled to four thousand ninety six pixels`() async throws {
        let url = try temporaryURL(extension: "png")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try writeImage(to: url, type: .png, width: 5000, height: 2)

        let image = try await AsciiImageDecoder.decode(url)

        #expect(max(image.cgImage.width, image.cgImage.height) == 4096)
    }

    @Test
    func `jpeg orientation is applied during decode`() async throws {
        let url = try temporaryURL(extension: "jpg")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try writeImage(
            to: url,
            type: .jpeg,
            width: 3,
            height: 2,
            orientation: .right
        )

        let image = try await AsciiImageDecoder.decode(url)

        #expect(image.cgImage.width == 2)
        #expect(image.cgImage.height == 3)
    }

    @Test
    func `canonical jpe extension is accepted as jpeg`() async throws {
        let url = try temporaryURL(extension: "jpe")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try writeImage(to: url, type: .jpeg)

        let image = try await AsciiImageDecoder.decode(url)

        #expect(image.cgImage.width == 2)
        #expect(image.cgImage.height == 2)
    }

    @Test
    func `unsupported raster data is rejected even with a png filename`() async throws {
        let url = try temporaryURL(extension: "png")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let gif = try #require(
            Data(base64Encoded: "R0lGODlhAQABAIAAAAAAAP///ywAAAAAAQABAAACAUwAOw==")
        )
        try gif.write(to: url)

        do {
            _ = try await AsciiImageDecoder.decode(url)
            Issue.record("Renamed GIF unexpectedly decoded as PNG")
        } catch let error as AsciiToolError {
            #expect(error == .unsupportedFormat)
        }
    }

    @Test
    func `animated png is rejected as unsupported`() async throws {
        let url = try temporaryURL(extension: "png")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try writeImage(to: url, type: .png, frameCount: 2)

        do {
            _ = try await AsciiImageDecoder.decode(url)
            Issue.record("Animated PNG unexpectedly decoded as a still image")
        } catch let error as AsciiToolError {
            #expect(error == .unsupportedFormat)
        }
    }

    @Test
    func `corrupt supported file reports decode failure`() async throws {
        let url = try temporaryURL(extension: "png")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try Data("not an image".utf8).write(to: url)

        do {
            _ = try await AsciiImageDecoder.decode(url)
            Issue.record("Corrupt PNG unexpectedly decoded")
        } catch let error as AsciiToolError {
            #expect(error == .decodeFailed)
        }
    }

    @Test
    func `files above fifty megabytes are rejected before decode`() async throws {
        let url = try temporaryURL(extension: "png")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: UInt64(AsciiImageDecoder.maximumFileSize + 1))
        try handle.close()

        do {
            _ = try await AsciiImageDecoder.decode(url)
            Issue.record("Oversized file unexpectedly decoded")
        } catch let error as AsciiToolError {
            #expect(error == .fileTooLarge)
        }
    }

    @Test
    func `declared raster dimensions reject decompression bombs before decode`() throws {
        do {
            try AsciiImageDecoder.validateDeclaredRasterDimensions(width: 30_000, height: 20_000)
            Issue.record("Oversized declared dimensions unexpectedly passed validation")
        } catch let error as AsciiToolError {
            #expect(error == .imageDimensionsTooLarge)
        }
    }

    @Test
    func `declared raster dimensions accept a bounded source`() throws {
        try AsciiImageDecoder.validateDeclaredRasterDimensions(width: 8_000, height: 4_000)
    }

    private func temporaryURL(extension fileExtension: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appending(path: "fixture.\(fileExtension)")
    }

    private func writeImage(
        to url: URL,
        type: UTType,
        width: Int = 2,
        height: Int = 2,
        alpha: UInt8 = 255,
        orientation: CGImagePropertyOrientation = .up,
        frameCount: Int = 1
    ) throws {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        pixels[3] = alpha
        let context = pixels.withUnsafeMutableBytes { bytes in
            CGContext(
                data: bytes.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        }
        let cgImage = try #require(context?.makeImage())
        let destination = try #require(
            CGImageDestinationCreateWithURL(
                url as CFURL,
                type.identifier as CFString,
                frameCount,
                nil
            ))
        for _ in 0..<frameCount {
            CGImageDestinationAddImage(
                destination,
                cgImage,
                [kCGImagePropertyOrientation: orientation.rawValue] as CFDictionary
            )
        }
        #expect(CGImageDestinationFinalize(destination))
    }
}
