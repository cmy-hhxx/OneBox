import MetalKit

@MainActor
final class AsciiMetalPipeline {
    let device: MTLDevice
    private let pipelineState: MTLRenderPipelineState
    private let samplerState: MTLSamplerState

    init(device: MTLDevice, library: MTLLibrary) throws {
        self.device = device
        guard
            let vertex = library.makeFunction(name: "asciiVertex"),
            let fragment = library.makeFunction(name: "asciiFragment")
        else {
            throw AsciiToolError.metalUnavailable
        }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = "OneBox ASCII Pipeline"
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        pipelineState = try device.makeRenderPipelineState(descriptor: descriptor)

        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        samplerDescriptor.sAddressMode = .clampToZero
        samplerDescriptor.tAddressMode = .clampToZero
        guard let sampler = device.makeSamplerState(descriptor: samplerDescriptor) else {
            throw AsciiToolError.metalUnavailable
        }
        samplerState = sampler
    }

    func makeTexture(from image: CGImage) throws -> MTLTexture {
        try MTKTextureLoader(device: device).newTexture(
            cgImage: image,
            options: [
                .SRGB: false,
                .origin: MTKTextureLoader.Origin.topLeft,
                .textureUsage: MTLTextureUsage.shaderRead.rawValue,
            ]
        )
    }

    func encode(
        commandBuffer: MTLCommandBuffer,
        renderPassDescriptor: MTLRenderPassDescriptor,
        sourceTexture: MTLTexture,
        glyphTexture: MTLTexture,
        snapshot: AsciiRenderSnapshot,
        time: Float
    ) throws {
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)
        else {
            throw AsciiToolError.metalUnavailable
        }
        var uniforms = AsciiUniforms(
            snapshot: snapshot,
            time: time,
            glyphCount: snapshot.glyphs.count
        )
        encoder.label = "OneBox ASCII Pass"
        encoder.setRenderPipelineState(pipelineState)
        encoder.setFragmentTexture(sourceTexture, index: 0)
        encoder.setFragmentTexture(glyphTexture, index: 1)
        encoder.setFragmentSamplerState(samplerState, index: 0)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<AsciiUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }
}
