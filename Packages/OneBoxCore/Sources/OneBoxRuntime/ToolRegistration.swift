import SwiftUI

@MainActor
public struct ToolRegistration: Identifiable {
    public let id: ToolID
    public let displayName: String
    public let systemImage: String
    public let summary: String

    private let makeContent: () -> AnyView
    private let onApplicationTermination: @MainActor () async -> Void

    public init<Content: View>(
        id: ToolID,
        displayName: String,
        systemImage: String = "square.grid.2x2",
        summary: String = "",
        onApplicationTermination: @escaping @MainActor () async -> Void = {},
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.id = id
        self.displayName = displayName
        self.systemImage = systemImage
        self.summary = summary
        self.makeContent = { AnyView(content()) }
        self.onApplicationTermination = onApplicationTermination
    }

    public func content() -> AnyView {
        makeContent()
    }

    public func prepareForApplicationTermination() async {
        await onApplicationTermination()
    }
}
