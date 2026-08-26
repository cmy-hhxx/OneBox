import Testing

@testable import AsciiArtTool

@MainActor
@Suite("ASCII module registration")
struct AsciiArtModuleTests {
    @Test
    func `module publishes the stable identity`() {
        let provider = TestAsciiMetalDeviceProvider(device: nil)
        let registration = AsciiArtModule.makeRegistration(deviceProvider: provider)

        #expect(registration.id.rawValue == "ascii-art")
        #expect(registration.displayName == "ASCII 工坊")
        #expect(provider.requestCount == 0)
    }
}
