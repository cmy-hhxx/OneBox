import AppKit

@MainActor
final class ApplicationTerminationCoordinator {
    typealias Preparation = @MainActor () async -> Void
    typealias Reply = @MainActor (Bool) -> Void

    private let timeout: Duration
    private var prepareForApplicationTermination: Preparation = {}
    private var terminationTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var pendingReply: Reply?
    private var hasStartedTermination = false
    private var didReply = false

    init(timeout: Duration = .seconds(15)) {
        self.timeout = timeout
    }

    func configure(_ preparation: @escaping Preparation) {
        prepareForApplicationTermination = preparation
    }

    func applicationShouldTerminate(
        reply: @escaping Reply
    ) -> NSApplication.TerminateReply {
        guard !hasStartedTermination else { return .terminateLater }
        hasStartedTermination = true
        pendingReply = reply

        let preparation = prepareForApplicationTermination
        terminationTask = Task { [weak self] in
            await preparation()
            self?.finishTermination(timedOut: false)
        }
        timeoutTask = Task { [weak self, timeout] in
            do {
                try await Task.sleep(for: timeout)
                self?.finishTermination(timedOut: true)
            } catch {
                // Normal completion cancels the deadline task.
            }
        }
        return .terminateLater
    }

    private func finishTermination(timedOut: Bool) {
        guard !didReply else { return }
        didReply = true
        if timedOut {
            terminationTask?.cancel()
        }
        timeoutTask?.cancel()
        pendingReply?(true)
        pendingReply = nil
    }
}

@MainActor
final class OneBoxApplicationDelegate: NSObject, NSApplicationDelegate {
    private let terminationCoordinator = ApplicationTerminationCoordinator()

    func configureApplicationTermination(
        _ preparation: @escaping ApplicationTerminationCoordinator.Preparation
    ) {
        terminationCoordinator.configure(preparation)
    }

    func applicationShouldTerminate(
        _ sender: NSApplication
    ) -> NSApplication.TerminateReply {
        terminationCoordinator.applicationShouldTerminate { shouldTerminate in
            sender.reply(toApplicationShouldTerminate: shouldTerminate)
        }
    }
}
