import Foundation

struct HTTPTransportResponse: @unchecked Sendable {
    let data: Data
    let response: HTTPURLResponse
}

struct HTTPDownloadResponse: @unchecked Sendable {
    let temporaryURL: URL
    let response: HTTPURLResponse
}

protocol HTTPTransporting: Sendable {
    func data(for request: URLRequest) async throws -> HTTPTransportResponse
    func download(for request: URLRequest) async throws -> HTTPDownloadResponse
    func download(
        for request: URLRequest,
        progress: @escaping @Sendable (DownloadProgressSnapshot) -> Void
    ) async throws -> HTTPDownloadResponse
    func download(
        for request: URLRequest,
        redirectValidator: @escaping @Sendable (URL, URL) -> Bool,
        progress: @escaping @Sendable (DownloadProgressSnapshot) -> Void
    ) async throws -> HTTPDownloadResponse
}

extension HTTPTransporting {
    func download(for request: URLRequest) async throws -> HTTPDownloadResponse {
        let response = try await data(for: request)
        let temporaryURL = FileManager.default.temporaryDirectory
            .appending(path: "podpin-http-\(UUID().uuidString)")
        try response.data.write(to: temporaryURL, options: .atomic)
        return HTTPDownloadResponse(temporaryURL: temporaryURL, response: response.response)
    }

    func download(
        for request: URLRequest,
        progress: @escaping @Sendable (DownloadProgressSnapshot) -> Void
    ) async throws -> HTTPDownloadResponse {
        progress(.indeterminate)
        let response = try await download(for: request)
        progress(.complete)
        return response
    }

    func download(
        for request: URLRequest,
        redirectValidator: @escaping @Sendable (URL, URL) -> Bool,
        progress: @escaping @Sendable (DownloadProgressSnapshot) -> Void
    ) async throws -> HTTPDownloadResponse {
        try await download(for: request, progress: progress)
    }
}

struct URLSessionHTTPTransport: HTTPTransporting {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func data(for request: URLRequest) async throws -> HTTPTransportResponse {
        do {
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse else {
                throw ContentImportError.malformedResponse
            }
            return HTTPTransportResponse(data: data, response: response)
        } catch is CancellationError {
            throw ContentImportError.cancelled
        } catch let error as ContentImportError {
            throw error
        } catch {
            throw ContentImportError.platformUnavailable("网络请求失败，请稍后重试。")
        }
    }

    func download(for request: URLRequest) async throws -> HTTPDownloadResponse {
        try await download(for: request, progress: { _ in })
    }

    func download(
        for request: URLRequest,
        progress: @escaping @Sendable (DownloadProgressSnapshot) -> Void
    ) async throws -> HTTPDownloadResponse {
        do {
            progress(.indeterminate)
            let response = try await HTTPDownloadOperation(
                session: session,
                request: request,
                progress: progress
            ).run()
            progress(.complete)
            return response
        } catch is CancellationError {
            throw ContentImportError.cancelled
        } catch let error as ContentImportError {
            throw error
        } catch {
            throw ContentImportError.platformUnavailable("网络请求失败，请稍后重试。")
        }
    }

    func download(
        for request: URLRequest,
        redirectValidator: @escaping @Sendable (URL, URL) -> Bool,
        progress: @escaping @Sendable (DownloadProgressSnapshot) -> Void
    ) async throws -> HTTPDownloadResponse {
        do {
            progress(.indeterminate)
            let response = try await HTTPDownloadOperation(
                session: session,
                request: request,
                redirectValidator: redirectValidator,
                progress: progress
            ).run()
            progress(.complete)
            return response
        } catch is CancellationError {
            throw ContentImportError.cancelled
        } catch let error as ContentImportError {
            throw error
        } catch {
            throw ContentImportError.platformUnavailable("网络请求失败，请稍后重试。")
        }
    }
}

private final class HTTPDownloadRedirectDelegate: NSObject, URLSessionTaskDelegate,
    @unchecked Sendable
{
    private let originalURL: URL
    private let redirectValidator: @Sendable (URL, URL) -> Bool

    init(
        originalURL: URL,
        redirectValidator: @escaping @Sendable (URL, URL) -> Bool
    ) {
        self.originalURL = originalURL
        self.redirectValidator = redirectValidator
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        guard let redirectedURL = request.url,
            redirectValidator(originalURL, redirectedURL)
        else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }
}

private final class HTTPDownloadOperation: @unchecked Sendable {
    private let baseSession: URLSession
    private let request: URLRequest
    private let redirectValidator: (@Sendable (URL, URL) -> Bool)?
    private let progress: @Sendable (DownloadProgressSnapshot) -> Void
    private let fileManager: FileManager
    private let lock = NSLock()
    private var ownedSession: URLSession?
    private var task: URLSessionDownloadTask?
    private var observation: NSKeyValueObservation?
    private var continuation: CheckedContinuation<HTTPDownloadResponse, Error>?
    private var isCancelled = false
    private var speedSampler = DownloadSpeedSampler()

    init(
        session: URLSession,
        request: URLRequest,
        redirectValidator: (@Sendable (URL, URL) -> Bool)? = nil,
        progress: @escaping @Sendable (DownloadProgressSnapshot) -> Void,
        fileManager: FileManager = .default
    ) {
        baseSession = session
        self.request = request
        self.redirectValidator = redirectValidator
        self.progress = progress
        self.fileManager = fileManager
    }

    func run() async throws -> HTTPDownloadResponse {
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                let ownedSession: URLSession?
                let session: URLSession
                if let redirectValidator, let originalURL = request.url {
                    let delegate = HTTPDownloadRedirectDelegate(
                        originalURL: originalURL,
                        redirectValidator: redirectValidator
                    )
                    let createdSession = URLSession(
                        configuration: baseSession.configuration,
                        delegate: delegate,
                        delegateQueue: nil
                    )
                    session = createdSession
                    ownedSession = createdSession
                } else {
                    session = baseSession
                    ownedSession = nil
                }
                let task = session.downloadTask(with: request) { [weak self] url, response, error in
                    self?.complete(temporaryURL: url, response: response, error: error)
                }
                let observation = task.progress.observe(
                    \.fractionCompleted, options: [.initial, .new]
                ) { [weak self] value, _ in
                    self?.reportProgress(value)
                }
                guard
                    install(
                        ownedSession: ownedSession,
                        task: task,
                        observation: observation,
                        continuation: continuation
                    )
                else {
                    observation.invalidate()
                    ownedSession?.invalidateAndCancel()
                    continuation.resume(throwing: CancellationError())
                    return
                }
                task.resume()
            }
        } onCancel: {
            cancel()
        }
    }

    private func reportProgress(_ value: Progress) {
        lock.lock()
        let speed = speedSampler.sample(
            completedBytes: value.completedUnitCount,
            at: ProcessInfo.processInfo.systemUptime
        )
        lock.unlock()
        progress(
            DownloadProgressSnapshot(
                fraction: value.totalUnitCount > 0 ? value.fractionCompleted : nil,
                bytesPerSecond: speed
            ))
    }

    private func complete(temporaryURL: URL?, response: URLResponse?, error: Error?) {
        if let error {
            finish(with: .failure(error))
            return
        }
        guard let temporaryURL, let response = response as? HTTPURLResponse else {
            finish(with: .failure(ContentImportError.malformedResponse))
            return
        }

        let stableURL = fileManager.temporaryDirectory
            .appending(path: "podpin-http-\(UUID().uuidString)")
        do {
            // URLSession owns and removes its download location when this
            // completion handler returns. Copying avoids racing that cleanup.
            try fileManager.copyItem(at: temporaryURL, to: stableURL)
            finish(
                with: .success(
                    HTTPDownloadResponse(
                        temporaryURL: stableURL,
                        response: response
                    )))
        } catch {
            finish(with: .failure(error))
        }
    }

    private func install(
        ownedSession: URLSession?,
        task: URLSessionDownloadTask,
        observation: NSKeyValueObservation,
        continuation: CheckedContinuation<HTTPDownloadResponse, Error>
    ) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !isCancelled else { return false }
        self.ownedSession = ownedSession
        self.task = task
        self.observation = observation
        self.continuation = continuation
        return true
    }

    private func cancel() {
        lock.lock()
        isCancelled = true
        let task = self.task
        lock.unlock()
        task?.cancel()
        finish(with: .failure(CancellationError()))
    }

    private func finish(with result: Result<HTTPDownloadResponse, Error>) {
        lock.lock()
        let continuation = self.continuation
        let observation = self.observation
        let ownedSession = self.ownedSession
        let shouldDiscardResult = isCancelled
        self.continuation = nil
        self.observation = nil
        self.ownedSession = nil
        task = nil
        lock.unlock()

        guard let continuation else {
            if shouldDiscardResult, case .success(let response) = result {
                try? fileManager.removeItem(at: response.temporaryURL)
            }
            return
        }
        observation?.invalidate()
        ownedSession?.finishTasksAndInvalidate()
        continuation.resume(with: result)
    }
}
