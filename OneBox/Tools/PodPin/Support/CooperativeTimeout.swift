import Foundation

enum CooperativeTimeoutResult<Value: Sendable>: Sendable {
    case value(Value)
    case timedOut
}

/// Races cancellable structured work against a deadline. The operation must
/// check cancellation between blocking framework calls so the task group can
/// drain promptly without leaving unowned work behind.
nonisolated func withCooperativeTimeout<Value: Sendable>(
    _ timeout: Duration,
    operation: @escaping @Sendable () async -> Value
) async -> CooperativeTimeoutResult<Value> {
    await withTaskGroup(of: CooperativeTimeoutResult<Value>.self) { group in
        group.addTask {
            .value(await operation())
        }
        group.addTask {
            do {
                try await Task.sleep(for: timeout)
                return .timedOut
            } catch {
                return .timedOut
            }
        }

        let first = await group.next() ?? .timedOut
        group.cancelAll()
        return first
    }
}
