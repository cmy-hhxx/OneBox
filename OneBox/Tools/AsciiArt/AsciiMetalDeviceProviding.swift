import Metal

@MainActor
public protocol AsciiMetalDeviceProviding {
    func makeDevice() -> MTLDevice?
}
