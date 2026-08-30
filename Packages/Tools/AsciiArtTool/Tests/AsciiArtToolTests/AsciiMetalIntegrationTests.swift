import ImageIO
import Metal
import Testing

@testable import AsciiArtTool

@MainActor
@Suite("ASCII Metal integration")
struct AsciiMetalIntegrationTests {
    @Test(.enabled(if: MTLCreateSystemDefaultDevice() != nil, "Metal device unavailable"))
    func `shader compiles and glyph atlas uploads`() async throws {
        let pipeline = try await AsciiRenderCache(
            deviceProvider: TestAsciiMetalDeviceProvider()
        ).preparedPipeline()

        let texture = try GlyphAtlas.makeTexture(glyphs: " 01", device: pipeline.device)

        #expect(texture.width == 192)
        #expect(texture.height == 64)
    }

    @Test
    func `unavailable injected device reports the typed metal failure`() async {
        let provider = TestAsciiMetalDeviceProvider(device: nil)
        let cache = AsciiRenderCache(deviceProvider: provider)

        do {
            _ = try await cache.preparedPipeline()
            Issue.record("Unavailable Metal device unexpectedly prepared a pipeline")
        } catch let error as AsciiToolError {
            #expect(error == .metalUnavailable)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
        #expect(provider.requestCount == 1)
    }

    @Test(.enabled(if: MTLCreateSystemDefaultDevice() != nil, "Metal device unavailable"))
    func `transparent export is static and uses the locked canvas size`() async throws {
        var settings = AsciiSettings()
        settings.hasTransparentBackground = true
        settings.animation = .wave
        settings.animationStrength = 1
        let image = try OneBoxSourceImage.make()
        let source = AsciiSource(image: image)
        let snapshot = AsciiRenderSnapshot(
            settings: settings,
            transform: CanvasTransform(),
            sourceSize: CGSize(width: image.width, height: image.height)
        )
        let cache = AsciiRenderCache(deviceProvider: TestAsciiMetalDeviceProvider())

        let first = try await AsciiPNGExporter.render(
            cache: cache,
            source: source,
            snapshot: snapshot
        )
        try await Task.sleep(for: .milliseconds(30))
        let second = try await AsciiPNGExporter.render(
            cache: cache,
            source: source,
            snapshot: snapshot
        )

        #expect(first == second)
        let imageSource = try #require(CGImageSourceCreateWithData(first as CFData, nil))
        let exported = try #require(CGImageSourceCreateImageAtIndex(imageSource, 0, nil))
        #expect(exported.width == 1024)
        #expect(exported.height == 1024)
        #expect(exported.alphaInfo != .none)
        #expect(try pixel(at: CGPoint(x: 0, y: 0), in: exported)[3] == 0)
    }

    @Test(.enabled(if: MTLCreateSystemDefaultDevice() != nil, "Metal device unavailable"))
    func `opaque png preserves the palette channel order`() async throws {
        var settings = AsciiSettings()
        settings.palettePreset = .cobalt
        settings.animation = .off
        let image = try OneBoxSourceImage.make()
        let data = try await AsciiPNGExporter.render(
            cache: AsciiRenderCache(deviceProvider: TestAsciiMetalDeviceProvider()),
            source: AsciiSource(image: image),
            snapshot: AsciiRenderSnapshot(
                settings: settings,
                transform: CanvasTransform(),
                sourceSize: CGSize(width: image.width, height: image.height)
            )
        )
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let exported = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))

        #expect(try pixel(at: CGPoint(x: 0, y: 0), in: exported) == [21, 87, 255, 255])
    }

    private func pixel(at point: CGPoint, in image: CGImage) throws -> [UInt8] {
        let crop = try #require(
            image.cropping(
                to: CGRect(x: point.x, y: point.y, width: 1, height: 1)
            )
        )
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = pixel.withUnsafeMutableBytes { bytes in
            CGContext(
                data: bytes.baseAddress,
                width: 1,
                height: 1,
                bitsPerComponent: 8,
                bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        }
        let graphicsContext = try #require(context)
        graphicsContext.draw(crop, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return pixel
    }
}
