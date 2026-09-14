import OneBoxRuntime

@MainActor
public enum AsciiArtModule {
    public static func makeRegistration(
        deviceProvider: any AsciiMetalDeviceProviding,
        diagnostics: ToolDiagnostics = .disabled
    ) -> ToolRegistration {
        let asyncWorkOwner = AsciiAsyncWorkOwner()
        let session = AsciiSession(asyncWorkOwner: asyncWorkOwner, diagnostics: diagnostics)
        let renderCache = AsciiRenderCache(
            deviceProvider: deviceProvider,
            asyncWorkOwner: asyncWorkOwner,
            diagnostics: diagnostics
        )
        return ToolRegistration(
            id: ToolID(rawValue: "ascii-art"),
            displayName: "ASCII 工坊",
            systemImage: "character.textbox",
            summary: "把图像转化为字符艺术",
            onApplicationTermination: {
                await session.shutdown()
            },
            content: {
                AsciiArtView(session: session, renderCache: renderCache)
            }
        )
    }
}
