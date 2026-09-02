import Darwin
@preconcurrency import Foundation

struct ExternalToolResult: Sendable, Equatable {
    let standardOutput: String
    let standardError: String
    let terminationStatus: Int32
}

protocol ExternalToolRunning: Sendable {
    func run(
        executableURL: URL,
        arguments: [String],
        workingDirectoryURL: URL?
    ) async throws -> ExternalToolResult
}

enum ExternalToolRunnerError: LocalizedError, Equatable {
    case timedOut

    var errorDescription: String? {
        switch self {
        case .timedOut: "外部媒体工具运行超时。"
        }
    }
}

/// Runs bundled tools without creating a shell. Source URLs are always individual
/// process arguments, so quotes, semicolons and spaces cannot become commands.
struct ProcessToolRunner: ExternalToolRunning {
    private let timeout: Duration

    init(timeout: Duration = .seconds(30 * 60)) {
        self.timeout = timeout
    }

    func run(
        executableURL: URL,
        arguments: [String],
        workingDirectoryURL: URL? = nil
    ) async throws -> ExternalToolResult {
        let processTask = Task {
            try await runProcess(
                executableURL: executableURL,
                arguments: arguments,
                workingDirectoryURL: workingDirectoryURL
            )
        }

        return try await withTaskCancellationHandler {
            try await withThrowingTaskGroup(of: ExternalToolResult.self) { group in
                group.addTask { try await processTask.value }
                group.addTask {
                    try await Task.sleep(for: timeout)
                    throw ExternalToolRunnerError.timedOut
                }
                do {
                    guard let result = try await group.next() else {
                        throw CancellationError()
                    }
                    processTask.cancel()
                    group.cancelAll()
                    return result
                } catch {
                    processTask.cancel()
                    group.cancelAll()
                    throw error
                }
            }
        } onCancel: {
            processTask.cancel()
        }
    }

    private func runProcess(
        executableURL: URL,
        arguments: [String],
        workingDirectoryURL: URL?
    ) async throws -> ExternalToolResult {
        let cancellationState = ProcessCancellationState()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                do {
                    let process = try SpawnedProcess(
                        executableURL: executableURL,
                        arguments: arguments,
                        workingDirectoryURL: workingDirectoryURL
                    )
                    process.startCollectingOutput()
                    guard
                        let processID = try cancellationState.start({
                            try process.spawn()
                        })
                    else {
                        process.close()
                        continuation.resume(throwing: CancellationError())
                        return
                    }
                    process.closeParentWriteEnds()
                    process.waitForExit(
                        processID: processID,
                        cancellationState: cancellationState,
                        continuation: continuation
                    )
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        } onCancel: {
            cancellationState.cancel()
        }
    }
}

/// `posix_spawn` places every tool invocation in its own process group before
/// it begins executing. That lets cancellation signal the complete tool tree
/// (for example, `yt-dlp` plus its FFmpeg child) instead of merely stopping the
/// top-level executable.
private final class SpawnedProcess: @unchecked Sendable {
    private let outputReader: FileHandle
    private let errorReader: FileHandle
    private let outputCollector = PipeCollector()
    private let errorCollector = PipeCollector()
    private let lock = NSLock()
    private var outputWriterFileDescriptor: Int32?
    private var errorWriterFileDescriptor: Int32?
    private let executablePath: String
    private let arguments: [String]
    private let workingDirectoryPath: String?

    init(
        executableURL: URL,
        arguments: [String],
        workingDirectoryURL: URL?
    ) throws {
        let outputPipe = try makePrivatePipe()
        let errorPipe: (reader: Int32, writer: Int32)
        do {
            errorPipe = try makePrivatePipe()
        } catch {
            _ = Darwin.close(outputPipe.reader)
            _ = Darwin.close(outputPipe.writer)
            throw error
        }

        outputReader = FileHandle(fileDescriptor: outputPipe.reader, closeOnDealloc: true)
        errorReader = FileHandle(fileDescriptor: errorPipe.reader, closeOnDealloc: true)
        outputWriterFileDescriptor = outputPipe.writer
        errorWriterFileDescriptor = errorPipe.writer
        executablePath = executableURL.path
        self.arguments = arguments
        workingDirectoryPath = workingDirectoryURL?.path
    }

    deinit {
        close()
    }

    func startCollectingOutput() {
        // A child can fill either pipe long before it exits. Draining as data
        // arrives prevents it from blocking forever on a full pipe.
        outputReader.readabilityHandler = { [outputCollector] handle in
            outputCollector.drain(handle)
        }
        errorReader.readabilityHandler = { [errorCollector] handle in
            errorCollector.drain(handle)
        }
    }

    func spawn() throws -> pid_t {
        let outputWriterFileDescriptor = try requireOutputWriterFileDescriptor()
        let errorWriterFileDescriptor = try requireErrorWriterFileDescriptor()

        var fileActions: posix_spawn_file_actions_t?
        try checkPOSIX(posix_spawn_file_actions_init(&fileActions))
        defer { posix_spawn_file_actions_destroy(&fileActions) }

        try checkPOSIX(
            posix_spawn_file_actions_adddup2(
                &fileActions,
                outputWriterFileDescriptor,
                STDOUT_FILENO
            ))
        try checkPOSIX(
            posix_spawn_file_actions_adddup2(
                &fileActions,
                errorWriterFileDescriptor,
                STDERR_FILENO
            ))
        try checkPOSIX(
            posix_spawn_file_actions_addclose(
                &fileActions,
                outputReader.fileDescriptor
            ))
        try checkPOSIX(
            posix_spawn_file_actions_addclose(
                &fileActions,
                errorReader.fileDescriptor
            ))
        try checkPOSIX(
            posix_spawn_file_actions_addclose(
                &fileActions,
                outputWriterFileDescriptor
            ))
        try checkPOSIX(
            posix_spawn_file_actions_addclose(
                &fileActions,
                errorWriterFileDescriptor
            ))
        if let workingDirectoryPath {
            try workingDirectoryPath.withCString {
                try checkPOSIX(posix_spawn_file_actions_addchdir_np(&fileActions, $0))
            }
        }

        var attributes: posix_spawnattr_t?
        try checkPOSIX(posix_spawnattr_init(&attributes))
        defer { posix_spawnattr_destroy(&attributes) }
        try checkPOSIX(
            posix_spawnattr_setflags(
                &attributes,
                Int16(POSIX_SPAWN_SETPGROUP)
            ))
        // POSIX defines a zero pgroup as the new child's own process ID.
        try checkPOSIX(posix_spawnattr_setpgroup(&attributes, 0))

        var processID: pid_t = 0
        let command = try CStringArguments([executablePath] + arguments)
        let result = command.withUnsafeMutablePointer { argv in
            executablePath.withCString {
                posix_spawn(
                    &processID,
                    $0,
                    &fileActions,
                    &attributes,
                    argv,
                    environ
                )
            }
        }
        try checkPOSIX(result)
        return processID
    }

    func closeParentWriteEnds() {
        lock.lock()
        let outputWriterFileDescriptor = self.outputWriterFileDescriptor
        let errorWriterFileDescriptor = self.errorWriterFileDescriptor
        self.outputWriterFileDescriptor = nil
        self.errorWriterFileDescriptor = nil
        lock.unlock()

        if let outputWriterFileDescriptor {
            _ = Darwin.close(outputWriterFileDescriptor)
        }
        if let errorWriterFileDescriptor {
            _ = Darwin.close(errorWriterFileDescriptor)
        }
    }

    func waitForExit(
        processID: pid_t,
        cancellationState: ProcessCancellationState,
        continuation: CheckedContinuation<ExternalToolResult, Error>
    ) {
        DispatchQueue.global(qos: .utility).async(execute: { [self] in
            do {
                let status = try waitForChild(processID)
                let output = outputCollector.finish(reading: outputReader)
                let error = errorCollector.finish(reading: errorReader)
                // Keep the group registered while draining. A parent can exit
                // before a descendant that inherited stdout/stderr; cancellation
                // must still be able to signal that descendant and close pipes.
                let wasCancelled = cancellationState.clear(processID: processID)
                close()

                if wasCancelled {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                continuation.resume(
                    returning: ExternalToolResult(
                        standardOutput: String(data: output, encoding: .utf8) ?? "",
                        standardError: String(data: error, encoding: .utf8) ?? "",
                        terminationStatus: terminationStatus(from: status)
                    ))
            } catch {
                let wasCancelled = cancellationState.clear(processID: processID)
                close()
                continuation.resume(throwing: wasCancelled ? CancellationError() : error)
            }
        })
    }

    func close() {
        closeParentWriteEnds()
        outputCollector.close(outputReader)
        errorCollector.close(errorReader)
    }

    private func requireOutputWriterFileDescriptor() throws -> Int32 {
        lock.lock()
        defer { lock.unlock() }
        guard let outputWriterFileDescriptor else { throw POSIXError(.EBADF) }
        return outputWriterFileDescriptor
    }

    private func requireErrorWriterFileDescriptor() throws -> Int32 {
        lock.lock()
        defer { lock.unlock() }
        guard let errorWriterFileDescriptor else { throw POSIXError(.EBADF) }
        return errorWriterFileDescriptor
    }
}

private func checkPOSIX(_ result: Int32) throws {
    guard result == 0 else {
        throw POSIXError(POSIXErrorCode(rawValue: result) ?? .EIO)
    }
}

private func currentPOSIXError() -> POSIXError {
    POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
}

/// Keeps every pipe endpoint above the standard streams. `posix_spawn` file
/// actions are ordered, so allowing `pipe()` to reuse fd 0/1/2 in a Finder
/// launch could accidentally close an already-redirected stdout or stderr.
private func makePrivatePipe() throws -> (reader: Int32, writer: Int32) {
    var rawPipe = [Int32](repeating: -1, count: 2)
    guard Darwin.pipe(&rawPipe) == 0 else { throw currentPOSIXError() }

    let reader = Darwin.fcntl(rawPipe[0], F_DUPFD, 3)
    guard reader >= 0 else {
        _ = Darwin.close(rawPipe[0])
        _ = Darwin.close(rawPipe[1])
        throw currentPOSIXError()
    }
    let writer = Darwin.fcntl(rawPipe[1], F_DUPFD, 3)
    guard writer >= 0 else {
        _ = Darwin.close(reader)
        _ = Darwin.close(rawPipe[0])
        _ = Darwin.close(rawPipe[1])
        throw currentPOSIXError()
    }

    _ = Darwin.close(rawPipe[0])
    _ = Darwin.close(rawPipe[1])
    return (reader, writer)
}

private func waitForChild(_ processID: pid_t) throws -> Int32 {
    var status: Int32 = 0
    while true {
        let waitedProcessID = Darwin.waitpid(processID, &status, 0)
        if waitedProcessID == processID {
            return status
        }
        if waitedProcessID == -1, errno == EINTR {
            continue
        }
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
}

private func terminationStatus(from waitStatus: Int32) -> Int32 {
    let terminatingSignal = waitStatus & 0x7F
    if terminatingSignal != 0 {
        return terminatingSignal
    }
    return (waitStatus >> 8) & 0xFF
}

/// Holds C strings until `posix_spawn` has consumed the complete argv array.
private final class CStringArguments {
    private var values: [UnsafeMutablePointer<CChar>?] = []

    init(_ strings: [String]) throws {
        for string in strings {
            guard let value = strdup(string) else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .ENOMEM)
            }
            values.append(value)
        }
        values.append(nil)
    }

    deinit {
        for case let value? in values {
            free(value)
        }
    }

    func withUnsafeMutablePointer<Result>(
        _ body: (UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>) throws -> Result
    ) rethrows -> Result {
        try values.withUnsafeMutableBufferPointer { buffer in
            try body(buffer.baseAddress!)
        }
    }
}

/// `FileHandle` callbacks and the process termination handler may run at the
/// same time. Serialising reads prevents a final drain from losing a chunk that
/// a readability callback has already consumed.
private final class PipeCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    private var finished = false

    func drain(_ handle: FileHandle) {
        lock.lock()
        defer { lock.unlock() }
        guard !finished else { return }

        let chunk = handle.availableData
        guard !chunk.isEmpty else {
            handle.readabilityHandler = nil
            return
        }
        data.append(chunk)
    }

    func finish(reading handle: FileHandle) -> Data {
        lock.lock()
        defer { lock.unlock() }
        guard !finished else { return data }

        finished = true
        handle.readabilityHandler = nil
        data.append(handle.readDataToEndOfFile())
        return data
    }

    func close(_ handle: FileHandle) {
        lock.lock()
        guard !finished else {
            lock.unlock()
            return
        }
        finished = true
        handle.readabilityHandler = nil
        lock.unlock()
        try? handle.close()
    }
}

/// Process-group registration and cancellation happen on separate executors.
/// Holding the lock across `posix_spawn` guarantees that a concurrent
/// cancellation either prevents a launch or signals the newly-created group.
private final class ProcessCancellationState: @unchecked Sendable {
    private let lock = NSLock()
    private var processID: pid_t?
    private var processGroupID: pid_t?
    private var cancelled = false

    func start(_ launch: () throws -> pid_t) throws -> pid_t? {
        lock.lock()
        defer { lock.unlock() }
        guard !cancelled else { return nil }
        let processID = try launch()
        self.processID = processID
        processGroupID = processID
        return processID
    }

    /// Clears the active process and returns whether the task was cancelled.
    func clear(processID: pid_t) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if self.processID == processID {
            self.processID = nil
            processGroupID = nil
        }
        return cancelled
    }

    func cancel() {
        let activeProcessID: pid_t?
        let activeProcessGroupID: pid_t?
        lock.lock()
        cancelled = true
        activeProcessID = processID
        activeProcessGroupID = processGroupID
        lock.unlock()

        guard let activeProcessID, let activeProcessGroupID else { return }
        _ = Darwin.killpg(activeProcessGroupID, SIGTERM)

        // A tool may inherit an ignored TERM disposition from its launcher.
        // Escalate only if this exact invocation is still draining after a short
        // grace period, so cancellation never leaves a downloader or encoder.
        let forceKill = DispatchWorkItem { [weak self] in
            self?.forceTerminateIfStillActive(
                processID: activeProcessID,
                processGroupID: activeProcessGroupID
            )
        }
        DispatchQueue.global(qos: .utility).asyncAfter(
            deadline: .now() + .milliseconds(250),
            execute: forceKill
        )
    }

    private func forceTerminateIfStillActive(
        processID: pid_t,
        processGroupID: pid_t
    ) {
        lock.lock()
        let shouldTerminate =
            cancelled
            && self.processID == processID
            && self.processGroupID == processGroupID
        lock.unlock()
        guard shouldTerminate else { return }
        _ = Darwin.killpg(processGroupID, SIGKILL)
    }
}

struct BundledToolLocator: Sendable {
    private let toolsDirectoryURL: URL?
    private let overrides: [String: URL]

    init(
        toolsDirectoryURL: URL? = nil,
        overrides: [String: URL] = [:]
    ) {
        self.toolsDirectoryURL = toolsDirectoryURL
        self.overrides = overrides
    }

    func executableURL(named name: String) throws -> URL {
        let candidate =
            overrides[name]
            ?? toolsDirectoryURL?.appending(
                path: name,
                directoryHint: .notDirectory
            )
        guard let candidate,
            candidate.isFileURL,
            FileManager.default.fileExists(atPath: candidate.path),
            FileManager.default.isExecutableFile(atPath: candidate.path)
        else {
            throw ContentImportError.toolUnavailable(name)
        }
        return candidate
    }
}
