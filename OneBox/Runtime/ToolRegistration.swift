import SwiftUI

@MainActor
public struct ToolRegistration: Identifiable {
    public let id: ToolID
    public let displayName: String

    private let makeContent: () -> AnyView

    public init<Content: View>(
        id: ToolID,
        displayName: String,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.id = id
        self.displayName = displayName
        self.makeContent = { AnyView(content()) }
    }

    public func content() -> AnyView {
        makeContent()
    }
}
