@preconcurrency import Metal

@MainActor
enum AsciiPNGExporter {
    static func render(
        cache: AsciiRenderCache,
        source: AsciiSource,
        snapshot: AsciiRenderSnapshot
    ) async throws -> Data {
        try Task.checkCancellation()
        let pipeline = try await cache.preparedPipeline()
        try Task.checkCancellation()
        let sourceTexture = try pipeline.makeTexture(from: source.image)
        let glyphTexture = try GlyphAtlas.makeTexture(
            glyphs: snapshot.glyphs,
            device: pipeline.device
        )

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: Int(snapshot.outputSize.width),
            height: Int(snapshot.outputSize.height),
            mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .shared
        guard let targetTexture = pipeline.device.makeTexture(descriptor: descriptor),
            let commandQueue = pipeline.device.makeCommandQueue(),
            let commandBuffer = commandQueue.makeCommandBuffer()
        else {
            throw AsciiToolError.exportFailed
        }

        let renderPass = MTLRenderPassDescriptor()
        renderPass.colorAttachments[0].texture = targetTexture
        renderPass.colorAttachments[0].loadAction = .clear
        renderPass.colorAttachments[0].storeAction = .store
        renderPass.colorAttachments[0].clearColor = MTLClearColor(
            red: 0, green: 0, blue: 0, alpha: 0)
        try pipeline.encode(
            commandBuffer: commandBuffer,
            renderPassDescriptor: renderPass,
            sourceTexture: sourceTexture,
            glyphTexture: glyphTexture,
            snapshot: snapshot,
            time: 0
        )

        try await commandBuffer.commitAndWait()
        try Task.checkCancellation()
        return try await PNGTextureEncoder.encode(texture: targetTexture)
    }
}

extension MTLCommandBuffer {
    fileprivate func commitAndWait() async throws {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            addCompletedHandler { commandBuffer in
                if let error = commandBuffer.error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
            commit()
        }
    }
}
