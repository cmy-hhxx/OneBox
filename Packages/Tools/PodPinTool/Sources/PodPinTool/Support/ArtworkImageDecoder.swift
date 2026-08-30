import CoreGraphics
import Foundation
@preconcurrency import QuickLookThumbnailing
import UniformTypeIdentifiers

private final class ArtworkRequestContinuation: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<CGImage?, Never>?
    private var completedImage: CGImage?
    private var isCompleted = false
    private var isCancelled = false

    func install(_ continuation: CheckedContinuation<CGImage?, Never>) -> Bool {
        lock.lock()
        if isCompleted {
            let completedImage = completedImage
            lock.unlock()
            continuation.resume(returning: completedImage)
            return false
        }
        self.continuation = continuation
        lock.unlock()
        return true
    }

    func resume(returning image: CGImage?) {
        lock.lock()
        guard !isCompleted else {
            lock.unlock()
            return
        }
        isCompleted = true
        completedImage = image
        let continuation = continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(returning: image)
    }

    func cancel() {
        lock.lock()
        isCancelled = true
        guard !isCompleted else {
            lock.unlock()
            return
        }
        isCompleted = true
        let continuation = continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(returning: nil)
    }

    func cancellationWasRequested() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return isCancelled
    }
}

struct ArtworkThumbnailGenerator: @unchecked Sendable {
    let generate:
        @Sendable (
            QLThumbnailGenerator.Request,
            @escaping @Sendable (CGImage?) -> Void
        ) -> Void
    let cancel: @Sendable (QLThumbnailGenerator.Request) -> Void

    static let system = ArtworkThumbnailGenerator(
        generate: { request, completion in
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) {
                representation,
                _ in
                completion(representation?.cgImage)
            }
        },
        cancel: { request in
            QLThumbnailGenerator.shared.cancel(request)
        }
    )
}

/// Uses Quick Look's cancellable request API instead of an uninterruptible
/// in-process ImageIO decode. Cancellation resumes the app waiter immediately,
/// rejects late callbacks, and asks the system generator to stop its request.
enum ArtworkImageDecoder {
    nonisolated static func thumbnail(
        at url: URL,
        maxPixelSize: Int
    ) async -> CGImage? {
        await thumbnail(
            at: url,
            maxPixelSize: maxPixelSize,
            generator: .system
        )
    }

    nonisolated static func thumbnail(
        at url: URL,
        maxPixelSize: Int,
        generator: ArtworkThumbnailGenerator
    ) async -> CGImage? {
        guard maxPixelSize > 0, !Task.isCancelled else { return nil }
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: maxPixelSize, height: maxPixelSize),
            scale: 1,
            representationTypes: .thumbnail
        )
        request.contentType = .image
        let requestContinuation = ArtworkRequestContinuation()

        let image = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard requestContinuation.install(continuation) else { return }
                guard !Task.isCancelled else {
                    generator.cancel(request)
                    requestContinuation.cancel()
                    return
                }
                generator.generate(request) { image in
                    requestContinuation.resume(returning: image)
                }
                if requestContinuation.cancellationWasRequested() {
                    generator.cancel(request)
                }
            }
        } onCancel: {
            requestContinuation.cancel()
            generator.cancel(request)
        }
        guard !Task.isCancelled else { return nil }
        return image
    }
}
