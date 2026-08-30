import Metal

@testable import AsciiArtTool

@MainActor
final class TestAsciiMetalDeviceProvider: AsciiMetalDeviceProviding {
    private(set) var requestCount = 0
    private let device: MTLDevice?

    init(device: MTLDevice? = MTLCreateSystemDefaultDevice()) {
        self.device = device
    }

    func makeDevice() -> MTLDevice? {
        requestCount += 1
        return device
    }
}
