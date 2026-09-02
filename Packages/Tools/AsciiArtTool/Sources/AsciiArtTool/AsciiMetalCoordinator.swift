import MetalKit

@MainActor
final class AsciiMetalCoordinator: NSObject, MTKViewDelegate {
    private let cache: AsciiRenderCache
    private let onReadinessChanged: (Bool) -> Void
    private var pipeline: AsciiMetalPipeline?
    private var commandQueue: MTLCommandQueue?
    private var sourceTexture: MTLTexture?
    private var glyphTexture: MTLTexture?
    private var snapshot: AsciiRenderSnapshot?
    private var sourceRevision = -1
    private var pendingSource: AsciiSource?
    private var pendingSourceRevision = -1
    private var glyphs = ""
    private var preparationTask: Task<Void, Never>?
    private var preparationFailed = false
    private var drawingFailed = false
    private var reportedReadiness: Bool?
    private var animationStartTime = ProcessInfo.processInfo.systemUptime
    private var lastRetryRevision = -1

    init(cache: AsciiRenderCache, onReadinessChanged: @escaping (Bool) -> Void) {
        self.cache = cache
        self.onReadinessChanged = onReadinessChanged
    }

    func update(
        view: MTKView,
        source: AsciiSource?,
        sourceRevision: Int,
        snapshot: AsciiRenderSnapshot?,
        isAnimating: Bool,
        retryRevision: Int
    ) {
        if retryRevision != lastRetryRevision {
            lastRetryRevision = retryRevision
            preparationFailed = false
            drawingFailed = false
            reportedReadiness = nil
        }
        self.snapshot = snapshot
        pendingSource = source
        pendingSourceRevision = sourceRevision
        configureDrawing(view: view, isAnimating: isAnimating)

        guard pipeline == nil else {
            guard !drawingFailed else {
                pauseDrawing(view: view)
                return
            }
            do {
                try updateTexturesIfNeeded(source: source, sourceRevision: sourceRevision)
                reportReadiness(true)
                requestStaticDrawIfNeeded(view: view, isAnimating: isAnimating)
            } catch {
                pauseDrawing(view: view)
                reportReadiness(false)
            }
            return
        }
        guard preparationTask == nil, !preparationFailed else { return }

        preparationTask = Task { @MainActor [weak self, weak view] in
            guard let self, let view else { return }
            do {
                let pipeline = try await cache.preparedPipeline()
                try Task.checkCancellation()
                guard let commandQueue = pipeline.device.makeCommandQueue() else {
                    throw AsciiToolError.metalUnavailable
                }
                self.pipeline = pipeline
                self.commandQueue = commandQueue
                view.device = pipeline.device
                try updateTexturesIfNeeded(
                    source: pendingSource,
                    sourceRevision: pendingSourceRevision
                )
                reportReadiness(true)
                requestStaticDrawIfNeeded(view: view, isAnimating: !view.isPaused)
            } catch is CancellationError {
                return
            } catch {
                preparationFailed = self.pipeline == nil
                pauseDrawing(view: view)
                reportReadiness(false)
            }
            preparationTask = nil
        }
    }

    func stop(view: MTKView) {
        view.isPaused = true
        preparationTask?.cancel()
        preparationTask = nil
        preparationFailed = false
        drawingFailed = false
        reportedReadiness = nil
        sourceTexture = nil
        glyphTexture = nil
        snapshot = nil
        sourceRevision = -1
        pendingSource = nil
        pendingSourceRevision = -1
        glyphs = ""
    }

    func draw(in view: MTKView) {
        guard
            let pipeline,
            let commandQueue,
            let sourceTexture,
            let glyphTexture,
            let snapshot,
            let descriptor = view.currentRenderPassDescriptor,
            let drawable = view.currentDrawable,
            let commandBuffer = commandQueue.makeCommandBuffer()
        else { return }

        let time: Float =
            view.isPaused
            ? 0
            : Float(ProcessInfo.processInfo.systemUptime - animationStartTime)
        do {
            try pipeline.encode(
                commandBuffer: commandBuffer,
                renderPassDescriptor: descriptor,
                sourceTexture: sourceTexture,
                glyphTexture: glyphTexture,
                snapshot: snapshot,
                time: time
            )
            commandBuffer.present(drawable)
            commandBuffer.commit()
        } catch {
            drawingFailed = true
            pauseDrawing(view: view)
            reportReadiness(false)
        }
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        if view.isPaused {
            view.setNeedsDisplay(view.bounds)
        }
    }

    private func configureDrawing(view: MTKView, isAnimating: Bool) {
        if isAnimating, view.isPaused {
            animationStartTime = ProcessInfo.processInfo.systemUptime
        }
        view.preferredFramesPerSecond = 60
        view.enableSetNeedsDisplay = !isAnimating
        view.isPaused = !isAnimating
    }

    private func requestStaticDrawIfNeeded(view: MTKView, isAnimating: Bool) {
        if !isAnimating {
            view.setNeedsDisplay(view.bounds)
        }
    }

    private func updateTexturesIfNeeded(source: AsciiSource?, sourceRevision: Int) throws {
        guard let pipeline, let snapshot, let source else { return }
        if self.sourceRevision != sourceRevision {
            sourceTexture = try pipeline.makeTexture(from: source.image)
            self.sourceRevision = sourceRevision
        }
        if glyphs != snapshot.glyphs {
            glyphTexture = try GlyphAtlas.makeTexture(
                glyphs: snapshot.glyphs,
                device: pipeline.device
            )
            glyphs = snapshot.glyphs
        }
    }

    private func pauseDrawing(view: MTKView) {
        view.isPaused = true
        view.enableSetNeedsDisplay = true
    }

    private func reportReadiness(_ isReady: Bool) {
        guard reportedReadiness != isReady else { return }
        reportedReadiness = isReady
        onReadinessChanged(isReady)
    }
}
