import Darwin
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
    func data(
        for request: URLRequest,
        redirectValidator: @escaping @Sendable (URL, URL) -> Bool
    ) async throws -> HTTPTransportResponse
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
    func data(
        for request: URLRequest,
        redirectValidator: @escaping @Sendable (URL, URL) -> Bool
    ) async throws -> HTTPTransportResponse {
        try await data(for: request)
    }

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
        } catch {
            if isURLSessionCancellation(error) { throw ContentImportError.cancelled }
            if let error = error as? ContentImportError { throw error }
            throw ContentImportError.platformUnavailable("网络请求失败，请稍后重试。")
        }
    }

    func data(
        for request: URLRequest,
        redirectValidator: @escaping @Sendable (URL, URL) -> Bool
    ) async throws -> HTTPTransportResponse {
        do {
            return try await HTTPDataOperation(
                session: session,
                request: request,
                redirectValidator: redirectValidator
            ).run()
        } catch {
            if isURLSessionCancellation(error) { throw ContentImportError.cancelled }
            if let error = error as? ContentImportError { throw error }
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
        } catch {
            if isURLSessionCancellation(error) { throw ContentImportError.cancelled }
            if let error = error as? ContentImportError { throw error }
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
        } catch {
            if isURLSessionCancellation(error) { throw ContentImportError.cancelled }
            if let error = error as? ContentImportError { throw error }
            throw ContentImportError.platformUnavailable("网络请求失败，请稍后重试。")
        }
    }
}

private func isURLSessionCancellation(_ error: Error) -> Bool {
    if error is CancellationError { return true }
    if let urlError = error as? URLError, urlError.code == .cancelled { return true }
    let nsError = error as NSError
    return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
}

private final class HTTPDataRedirectDelegate: NSObject, URLSessionTaskDelegate,
    @unchecked Sendable
{
    private let originalURL: URL
    private let redirectValidator: @Sendable (URL, URL) -> Bool
    private let onRejected: @Sendable () -> Void

    init(
        originalURL: URL,
        redirectValidator: @escaping @Sendable (URL, URL) -> Bool,
        onRejected: @escaping @Sendable () -> Void
    ) {
        self.originalURL = originalURL
        self.redirectValidator = redirectValidator
        self.onRejected = onRejected
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
            onRejected()
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }
}

private final class HTTPDataOperation: @unchecked Sendable {
    private let baseSession: URLSession
    private let request: URLRequest
    private let redirectValidator: @Sendable (URL, URL) -> Bool
    private let lock = NSLock()
    private var ownedSession: URLSession?
    private var task: URLSessionDataTask?
    private var continuation: CheckedContinuation<HTTPTransportResponse, Error>?
    private var isCancelled = false

    init(
        session: URLSession,
        request: URLRequest,
        redirectValidator: @escaping @Sendable (URL, URL) -> Bool
    ) {
        baseSession = session
        self.request = request
        self.redirectValidator = redirectValidator
    }

    func run() async throws -> HTTPTransportResponse {
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                guard let originalURL = request.url else {
                    continuation.resume(throwing: ContentImportError.malformedResponse)
                    return
                }
                let operation = self
                let delegate = HTTPDataRedirectDelegate(
                    originalURL: originalURL,
                    redirectValidator: redirectValidator,
                    onRejected: { [weak operation] in
                        operation?.rejectRedirect()
                    }
                )
                let ownedSession = URLSession(
                    configuration: baseSession.configuration,
                    delegate: delegate,
                    delegateQueue: nil
                )
                let task = ownedSession.dataTask(with: request) {
                    [weak self] data, response, error in
                    self?.complete(data: data, response: response, error: error)
                }
                guard
                    install(
                        ownedSession: ownedSession,
                        task: task,
                        continuation: continuation
                    )
                else {
                    ownedSession.invalidateAndCancel()
                    continuation.resume(throwing: CancellationError())
                    return
                }
                task.resume()
            }
        } onCancel: {
            cancel()
        }
    }

    private func install(
        ownedSession: URLSession,
        task: URLSessionDataTask,
        continuation: CheckedContinuation<HTTPTransportResponse, Error>
    ) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !isCancelled else { return false }
        self.ownedSession = ownedSession
        self.task = task
        self.continuation = continuation
        return true
    }

    private func rejectRedirect() {
        finish(with: .failure(ContentImportError.malformedResponse))
    }

    private func complete(data: Data?, response: URLResponse?, error: Error?) {
        if let error {
            finish(with: .failure(error))
            return
        }
        guard let data, let response = response as? HTTPURLResponse else {
            finish(with: .failure(ContentImportError.malformedResponse))
            return
        }
        finish(with: .success(HTTPTransportResponse(data: data, response: response)))
    }

    private func cancel() {
        lock.lock()
        isCancelled = true
        let task = self.task
        lock.unlock()
        task?.cancel()
        finish(with: .failure(CancellationError()))
    }

    private func finish(with result: Result<HTTPTransportResponse, Error>) {
        lock.lock()
        let continuation = self.continuation
        let ownedSession = self.ownedSession
        self.continuation = nil
        self.ownedSession = nil
        self.task = nil
        lock.unlock()
        guard let continuation else { return }
        ownedSession?.finishTasksAndInvalidate()
        continuation.resume(with: result)
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
            // completion handler returns. Move it into our ownership without
            // copying the full payload; only cross-volume moves need a copy.
            do {
                try fileManager.moveItem(at: temporaryURL, to: stableURL)
            } catch  where Self.isCrossDeviceMoveError(error) {
                try fileManager.copyItem(at: temporaryURL, to: stableURL)
            }
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

    private static func isCrossDeviceMoveError(_ error: Error) -> Bool {
        let error = error as NSError
        if error.domain == NSPOSIXErrorDomain, error.code == Int(EXDEV) {
            return true
        }
        guard let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError else {
            return false
        }
        return isCrossDeviceMoveError(underlying)
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
