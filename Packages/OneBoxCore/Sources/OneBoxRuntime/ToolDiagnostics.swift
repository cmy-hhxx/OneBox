import Foundation

public struct DiagnosticEvent: Sendable {
    public let timestamp: Date
    public let operation: String
    public let message: String

    public init(timestamp: Date = Date(), operation: String, message: String) {
        self.timestamp = timestamp
        self.operation = operation
        self.message = message
    }
}

/// A module-bound sink. Tools report at the boundary before translating errors for presentation.
public struct ToolDiagnostics: Sendable {
    private let receive: @Sendable (DiagnosticEvent) -> Void

    public static let disabled = ToolDiagnostics { _ in }

    public init(receive: @escaping @Sendable (DiagnosticEvent) -> Void) {
        self.receive = receive
    }

    public func record(_ error: any Error, operation: String) {
        let nsError = error as NSError
        guard !(error is CancellationError),
            !(nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled),
            !(nsError.domain == NSCocoaErrorDomain && nsError.code == NSUserCancelledError)
        else { return }
        record(message: Self.describe(error), operation: operation)
    }

    public func record(message: String, operation: String) {
        receive(DiagnosticEvent(operation: operation, message: message))
    }

    private static func describe(_ error: any Error) -> String {
        var current = error as NSError
        var visited = Set<ObjectIdentifier>()
        var descriptions: [String] = []
        while visited.insert(ObjectIdentifier(current)).inserted {
            var lines = ["\(current.domain) (\(current.code))", current.localizedDescription]
            if let reason = current.localizedFailureReason { lines.append(reason) }
            if let description = current.userInfo[NSDebugDescriptionErrorKey] as? String {
                lines.append(description)
            }
            descriptions.append(lines.joined(separator: "\n"))
            guard let underlying = current.userInfo[NSUnderlyingErrorKey] as? NSError else { break }
            current = underlying
        }
        if descriptions.count > 1 { return descriptions.last ?? "" }
        let description = descriptions.first ?? ""
        if type(of: error) is NSError.Type { return description }
        let reflected = String(reflecting: error)
        return description.contains(reflected) ? description : description + "\n\n" + reflected
    }
}
