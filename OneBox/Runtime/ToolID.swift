public struct ToolID: RawRepresentable, Hashable, Identifiable, Sendable {
    public let rawValue: String

    public var id: String { rawValue }

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}
