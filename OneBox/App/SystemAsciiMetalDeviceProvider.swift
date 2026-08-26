import AsciiArtTool
import Metal

@MainActor
struct SystemAsciiMetalDeviceProvider: AsciiMetalDeviceProviding {
    func makeDevice() -> MTLDevice? {
        MTLCreateSystemDefaultDevice()
    }
}
