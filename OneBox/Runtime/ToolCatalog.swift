public struct ToolCatalog {
    public let registrations: [ToolRegistration]

    public init(registrations: [ToolRegistration]) {
        precondition(
            Set(registrations.map(\.id)).count == registrations.count,
            "Tool registrations must use unique IDs."
        )
        self.registrations = registrations
    }

    public func registration(for id: ToolID?) -> ToolRegistration? {
        registrations.first { $0.id == id }
    }
}
