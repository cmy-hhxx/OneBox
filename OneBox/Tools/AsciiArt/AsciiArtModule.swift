import OneBoxRuntime

@MainActor
public enum AsciiArtModule {
    public static func makeRegistration(
        deviceProvider: any AsciiMetalDeviceProviding
    ) -> ToolRegistration {
        let session = AsciiSession()
        let renderCache = AsciiRenderCache(deviceProvider: deviceProvider)
        return ToolRegistration(
            id: ToolID(rawValue: "ascii-art"),
            displayName: "ASCII 工坊"
        ) {
            AsciiArtView(session: session, renderCache: renderCache)
        }
    }
}
