import Foundation

struct AsciiTimeoutError: Error, Equatable, Sendable {}

final class AsciiAsyncWorkOwner: @unchecked Sendable {
    private let lock = NSLock()
    private var tasks: [UUID: AsciiOwnedTask] = [:]

    var activeTaskCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return tasks.count
    }

    fileprivate func start(
        operation: @escaping @Sendable () async -> Void
    ) -> Task<Void, Never> {
        let id = UUID()
        let ownedTask = AsciiOwnedTask()
        lock.lock()
        tasks[id] = ownedTask
        lock.unlock()

        let task = Task { [weak self] in
            await operation()
            self?.finish(id: id)
        }
        ownedTask.install(task)
        return task
    }

    func cancelAll() {
        let ownedTasks = snapshot()
        for task in ownedTasks {
            task.cancel()
        }
    }

    func cancelAndWait() async {
        _ = await cancelAndWait(upTo: nil)
    }

    /// Requests cancellation and waits only while the owner drains. A deadline
    /// is required for lifecycle shutdown because framework work may ignore it.
    @discardableResult
    func cancelAndWait(upTo timeout: Duration?) async -> Bool {
        cancelAll()
        let clock = ContinuousClock()
        let deadline = timeout.map { clock.now.advanced(by: $0) }
        while activeTaskCount > 0 {
            if Task.isCancelled {
                return false
            }
            if let deadline, clock.now >= deadline {
                return false
            }
            if let deadline {
                let remaining = clock.now.duration(to: deadline)
                try? await Task.sleep(for: min(remaining, .milliseconds(10)))
            } else {
                await Task.yield()
            }
        }
        return true
    }

    private func snapshot() -> [AsciiOwnedTask] {
        lock.lock()
        defer { lock.unlock() }
        return Array(tasks.values)
    }

    private func finish(id: UUID) {
        lock.lock()
        let ownedTask = tasks.removeValue(forKey: id)
        lock.unlock()
        ownedTask?.complete()
    }

    deinit { cancelAll() }
}

private final class AsciiOwnedTask: @unchecked Sendable {
    private let lock = NSLock()
    private var storedTask: Task<Void, Never>?
    private var isCancellationRequested = false
    private var isComplete = false

    var task: Task<Void, Never>? {
        lock.lock()
        defer { lock.unlock() }
        return storedTask
    }

    func install(_ task: Task<Void, Never>) {
        lock.lock()
        guard !isComplete else {
            lock.unlock()
            return
        }
        storedTask = task
        let shouldCancel = isCancellationRequested
        lock.unlock()
        if shouldCancel {
            task.cancel()
        }
    }

    func cancel() {
        lock.lock()
        isCancellationRequested = true
        let task = storedTask
        lock.unlock()
        task?.cancel()
    }

    func complete() {
        lock.lock()
        isComplete = true
        storedTask = nil
        lock.unlock()
    }
}

enum AsciiAsyncDeadline {
    static let imageImport: Duration = .seconds(15)
    static let pipelinePreparation: Duration = .seconds(10)
    static let pngExport: Duration = .seconds(15)

    static func run<Value: Sendable>(
        for timeout: Duration,
        owner: AsciiAsyncWorkOwner,
        operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        let state = AsciiDeadlineRaceState<Value>()
        let result = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                state.start(
                    continuation: continuation,
                    timeout: timeout,
                    owner: owner,
                    operation: operation
                )
            }
        } onCancel: {
            state.resolve(.failure(CancellationError()))
        }
        return try result.get()
    }
}

private final class AsciiDeadlineRaceState<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Result<Value, Error>, Never>?
    private var operationTask: Task<Void, Never>?
    private var deadlineTask: Task<Void, Never>?
    private var resolved = false

    func start(
        continuation: CheckedContinuation<Result<Value, Error>, Never>,
        timeout: Duration,
        owner: AsciiAsyncWorkOwner,
        operation: @escaping @Sendable () async throws -> Value
    ) {
        lock.lock()
        guard !resolved else {
            lock.unlock()
            continuation.resume(returning: .failure(CancellationError()))
            return
        }
        self.continuation = continuation
        operationTask = owner.start { [weak self] in
            do {
                self?.resolve(.success(try await operation()))
            } catch {
                self?.resolve(.failure(error))
            }
        }
        deadlineTask = Task { [weak self] in
            do {
                try await Task.sleep(for: timeout)
                self?.resolve(.failure(AsciiTimeoutError()))
            } catch {
                // The operation or parent cancellation already resolved the race.
            }
        }
        lock.unlock()
    }

    func resolve(_ result: Result<Value, Error>) {
        lock.lock()
        guard !resolved else {
            lock.unlock()
            return
        }
        resolved = true
        let continuation = continuation
        self.continuation = nil
        let operationTask = operationTask
        self.operationTask = nil
        let deadlineTask = deadlineTask
        self.deadlineTask = nil
        lock.unlock()

        operationTask?.cancel()
        deadlineTask?.cancel()
        continuation?.resume(returning: result)
    }
}
