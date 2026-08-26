import Metal

@MainActor
final class AsciiRenderCache {
    private let deviceProvider: any AsciiMetalDeviceProviding
    private var pipeline: AsciiMetalPipeline?

    init(deviceProvider: any AsciiMetalDeviceProviding) {
        self.deviceProvider = deviceProvider
    }

    func preparedPipeline() async throws -> AsciiMetalPipeline {
        if let pipeline { return pipeline }

        guard let device = deviceProvider.makeDevice() else {
            throw AsciiToolError.metalUnavailable
        }
        let result = try await AsciiAsyncDeadline.run(
            for: AsciiAsyncDeadline.pipelinePreparation
        ) {
            let library = try await device.makeLibrary(
                source: AsciiShaderSource.source, options: nil)
            try Task.checkCancellation()
            return try await AsciiMetalPipeline(device: device, library: library)
        }
        try Task.checkCancellation()
        pipeline = result
        return result
    }
}
