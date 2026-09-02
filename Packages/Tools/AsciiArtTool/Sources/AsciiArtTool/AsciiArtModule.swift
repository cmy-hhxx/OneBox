import OneBoxRuntime

@MainActor
public enum AsciiArtModule {
    public static func makeRegistration(
        deviceProvider: any AsciiMetalDeviceProviding
    ) -> ToolRegistration {
        let asyncWorkOwner = AsciiAsyncWorkOwner()
        let session = AsciiSession(asyncWorkOwner: asyncWorkOwner)
        let renderCache = AsciiRenderCache(
            deviceProvider: deviceProvider,
            asyncWorkOwner: asyncWorkOwner
        )
        return ToolRegistration(
            id: ToolID(rawValue: "ascii-art"),
            displayName: "ASCII 工坊",
            onApplicationTermination: {
                await session.shutdown()
            },
            content: {
                AsciiArtView(session: session, renderCache: renderCache)
            }
        )
    }
}
