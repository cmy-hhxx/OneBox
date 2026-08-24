import SwiftUI

public struct ToolRegistration: Identifiable {
    public let id: ToolID
    public let displayName: String
    public let activation: ToolActivation

    private let makeContent: (ToolContext) -> AnyView

    public init<Content: View>(
        id: ToolID,
        displayName: String,
        activation: ToolActivation = .onOpen,
        @ViewBuilder content: @escaping (ToolContext) -> Content
    ) {
        self.id = id
        self.displayName = displayName
        self.activation = activation
        self.makeContent = { context in AnyView(content(context)) }
    }

    public func content(context: ToolContext) -> AnyView {
        makeContent(context)
    }
}
