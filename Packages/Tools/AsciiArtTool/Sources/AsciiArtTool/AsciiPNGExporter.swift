@preconcurrency import Metal

enum AsciiPNGExporter {
    @MainActor
    static func render(
        cache: AsciiRenderCache,
        source: AsciiSource,
        snapshot: AsciiRenderSnapshot
    ) async throws -> Data {
        try Task.checkCancellation()
        let pipeline = try await cache.preparedPipeline()
        try Task.checkCancellation()
        return try await renderPrepared(
            pipeline: pipeline,
            source: source,
            snapshot: snapshot
        )
    }

    @concurrent
    static func renderPrepared(
        pipeline: AsciiMetalPipeline,
        source: AsciiSource,
        snapshot: AsciiRenderSnapshot
    ) async throws -> Data {
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
        let waiter = MTLCommandBufferWaiter(commandBuffer: self)
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await waiter.wait()
        } onCancel: {
            waiter.cancel()
        }
    }
}

private final class MTLCommandBufferWaiter: @unchecked Sendable {
    private let commandBuffer: MTLCommandBuffer
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?
    private var isResolved = false
    private var isCancelled = false

    init(commandBuffer: MTLCommandBuffer) {
        self.commandBuffer = commandBuffer
    }

    func wait() async throws {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            lock.lock()
            guard !isResolved else {
                lock.unlock()
                continuation.resume(throwing: CancellationError())
                return
            }
            if isCancelled {
                isResolved = true
                lock.unlock()
                continuation.resume(throwing: CancellationError())
                return
            }
            self.continuation = continuation
            lock.unlock()

            commandBuffer.addCompletedHandler { [weak self] commandBuffer in
                self?.complete(with: commandBuffer.error)
            }

            lock.lock()
            let shouldCancel = isCancelled
            lock.unlock()
            if shouldCancel {
                complete(with: CancellationError())
            } else {
                commandBuffer.commit()
            }
        }
    }

    func cancel() {
        lock.lock()
        isCancelled = true
        let continuation = self.continuation
        self.continuation = nil
        let shouldCancel = !isResolved
        isResolved = true
        lock.unlock()

        guard shouldCancel else { return }
        continuation?.resume(throwing: CancellationError())
    }

    private func complete(with error: Error?) {
        lock.lock()
        guard !isResolved else {
            lock.unlock()
            return
        }
        isResolved = true
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(with: error.map(Result.failure) ?? .success(()))
    }
}
