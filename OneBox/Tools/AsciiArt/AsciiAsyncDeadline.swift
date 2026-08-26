import Foundation

struct AsciiTimeoutError: Error, Equatable, Sendable {}

enum AsciiAsyncDeadline {
    static let imageImport: Duration = .seconds(15)
    static let pipelinePreparation: Duration = .seconds(10)
    static let pngExport: Duration = .seconds(15)

    static func run<Value: Sendable>(
        for timeout: Duration,
        operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        try await withThrowingTaskGroup(of: Value.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw AsciiTimeoutError()
            }
            defer { group.cancelAll() }
            guard let value = try await group.next() else {
                throw CancellationError()
            }
            return value
        }
    }
}
