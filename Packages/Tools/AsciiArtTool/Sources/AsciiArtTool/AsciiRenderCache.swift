import Metal
import OneBoxRuntime

@MainActor
final class AsciiRenderCache {
    let diagnostics: ToolDiagnostics
    private let deviceProvider: any AsciiMetalDeviceProviding
    private let asyncWorkOwner: AsciiAsyncWorkOwner
    private var pipeline: AsciiMetalPipeline?

    init(
        deviceProvider: any AsciiMetalDeviceProviding,
        asyncWorkOwner: AsciiAsyncWorkOwner = AsciiAsyncWorkOwner(),
        diagnostics: ToolDiagnostics = .disabled
    ) {
        self.diagnostics = diagnostics
        self.deviceProvider = deviceProvider
        self.asyncWorkOwner = asyncWorkOwner
    }

    func preparedPipeline() async throws -> AsciiMetalPipeline {
        if let pipeline { return pipeline }

        guard let device = deviceProvider.makeDevice() else {
            throw AsciiToolError.metalUnavailable
        }
        let result = try await AsciiAsyncDeadline.run(
            for: AsciiAsyncDeadline.pipelinePreparation,
            owner: asyncWorkOwner
        ) {
            let library = try await device.makeLibrary(
                source: AsciiShaderSource.source, options: nil)
            try Task.checkCancellation()
            return try AsciiMetalPipeline(device: device, library: library)
        }
        try Task.checkCancellation()
        pipeline = result
        return result
    }
}
