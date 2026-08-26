import CoreGraphics
@preconcurrency import Metal
import Testing

@testable import AsciiArtTool

@MainActor
@Suite("ASCII palette golden outputs")
struct AsciiPaletteGoldenTests {
    @Test(
        .enabled(if: MTLCreateSystemDefaultDevice() != nil, "Metal device unavailable"),
        arguments: [
            (AsciiPalettePreset.oneBox, [246, 242, 244, 255]),
            (AsciiPalettePreset.paper, [244, 244, 244, 255]),
            (AsciiPalettePreset.inverse, [11, 11, 11, 255]),
            (AsciiPalettePreset.cobalt, [255, 94, 31, 255]),
            (AsciiPalettePreset.prism, [252, 244, 247, 255]),
            (AsciiPalettePreset.terminal, [3, 12, 4, 255]),
            (AsciiPalettePreset.signal, [51, 46, 230, 255]),
        ]
    )
    func `small render matches its tolerant golden signature`(
        preset: AsciiPalettePreset,
        expected: [Int]
    ) async throws {
        let signature = try await renderSignature(preset: preset)

        #expect(
            zip(signature, expected).allSatisfy { abs($0 - $1) <= 3 },
            "\(preset.rawValue) signature was \(signature)"
        )
    }

    private func renderSignature(preset: AsciiPalettePreset) async throws -> [Int] {
        var settings = AsciiSettings()
        settings.palettePreset = preset
        settings.animation = .off
        settings.characterSize = 20
        let image = try makeGoldenSource()
        let snapshot = AsciiRenderSnapshot(
            settings: settings,
            transform: CanvasTransform(),
            sourceSize: CGSize(width: image.width, height: image.height)
        )
        let pipeline = try await AsciiRenderCache(
            deviceProvider: TestAsciiMetalDeviceProvider()
        ).preparedPipeline()
        let sourceTexture = try pipeline.makeTexture(from: image)
        let glyphTexture = try GlyphAtlas.makeTexture(
            glyphs: snapshot.glyphs, device: pipeline.device)
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: 64,
            height: 64,
            mipmapped: false
        )
        descriptor.usage = [.renderTarget]
        descriptor.storageMode = .shared
        let target = try #require(pipeline.device.makeTexture(descriptor: descriptor))
        let queue = try #require(pipeline.device.makeCommandQueue())
        let commandBuffer = try #require(queue.makeCommandBuffer())
        let renderPass = MTLRenderPassDescriptor()
        renderPass.colorAttachments[0].texture = target
        renderPass.colorAttachments[0].loadAction = .clear
        renderPass.colorAttachments[0].storeAction = .store
        try pipeline.encode(
            commandBuffer: commandBuffer,
            renderPassDescriptor: renderPass,
            sourceTexture: sourceTexture,
            glyphTexture: glyphTexture,
            snapshot: snapshot,
            time: 0
        )
        commandBuffer.commit()
        await commandBuffer.completed()

        var bytes = [UInt8](repeating: 0, count: 64 * 64 * 4)
        target.getBytes(
            &bytes,
            bytesPerRow: 64 * 4,
            from: MTLRegionMake2D(0, 0, 64, 64),
            mipmapLevel: 0
        )
        var totals = [Int](repeating: 0, count: 4)
        for index in stride(from: 0, to: bytes.count, by: 4) {
            totals[0] += Int(bytes[index])
            totals[1] += Int(bytes[index + 1])
            totals[2] += Int(bytes[index + 2])
            totals[3] += Int(bytes[index + 3])
        }
        return totals.map { $0 / (64 * 64) }
    }

    private func makeGoldenSource() throws -> CGImage {
        let context = try #require(
            CGContext(
                data: nil,
                width: 64,
                height: 64,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 32, height: 64))
        return try #require(context.makeImage())
    }
}
