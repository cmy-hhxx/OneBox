import Foundation
import Observation
import OneBoxRuntime

@MainActor
@Observable
final class AsciiSession {
    var settings = AsciiSettings()
    var transform = CanvasTransform()
    var isInspectorPresented = false
    private(set) var source: AsciiSource?
    private(set) var sourceRevision = 0
    private(set) var isImporting = false
    private(set) var isMetalReady = false
    private(set) var metalRetryRevision = 0

    private var isVisible = false
    private var isSceneActive = true
    private var isWindowVisible = true
    private var reduceMotion = false
    private var wantsPlayback = true
    private var manuallyEnabledWithReduceMotion = false
    private var importGeneration = 0
    private var operationError: AsciiToolError?
    private var isMetalUnavailable = false
    private(set) var allowsTransientWork = true
    @ObservationIgnored private var importTask: Task<Void, Never>?
    @ObservationIgnored let asyncWorkOwner: AsciiAsyncWorkOwner

    let diagnostics: ToolDiagnostics

    init(
        asyncWorkOwner: AsciiAsyncWorkOwner = AsciiAsyncWorkOwner(),
        diagnostics: ToolDiagnostics = .disabled
    ) {
        self.diagnostics = diagnostics
        self.asyncWorkOwner = asyncWorkOwner
    }

    var statusError: AsciiToolError? {
        isMetalUnavailable ? .metalUnavailable : operationError
    }

    var selectedCharacterSet: AsciiCharacterSet {
        get { settings.characters.selection }
        set { settings.characters.select(newValue) }
    }

    var customCharacters: String {
        get { settings.characters.customInput }
        set { settings.characters.updateCustom(newValue) }
    }

    var selectedAnimation: AsciiAnimation {
        get { settings.animation }
        set { settings.animation = newValue }
    }

    var statusMessage: String? {
        statusError?.actionMessage
    }

    var renderSnapshot: AsciiRenderSnapshot? {
        guard let source else { return nil }
        return AsciiRenderSnapshot(
            settings: settings,
            transform: transform,
            sourceSize: CGSize(width: source.image.width, height: source.image.height)
        )
    }

    var isAnimationActive: Bool {
        isVisible && isSceneActive && isWindowVisible && settings.animation != .off && wantsPlayback
            && (!reduceMotion || manuallyEnabledWithReduceMotion)
    }

    func setVisible(_ isVisible: Bool) {
        self.isVisible = isVisible
    }

    func setSceneActive(_ isSceneActive: Bool) {
        self.isSceneActive = isSceneActive
    }

    func setWindowVisible(_ isWindowVisible: Bool) {
        self.isWindowVisible = isWindowVisible
    }

    func setReduceMotion(_ reduceMotion: Bool) {
        self.reduceMotion = reduceMotion
        if !reduceMotion {
            manuallyEnabledWithReduceMotion = false
        }
    }

    func togglePlayback() {
        guard settings.animation != .off else { return }
        if reduceMotion, !manuallyEnabledWithReduceMotion {
            manuallyEnabledWithReduceMotion = true
            wantsPlayback = true
        } else {
            wantsPlayback.toggle()
            if !wantsPlayback {
                manuallyEnabledWithReduceMotion = false
            }
        }
    }

    func prepareInitialSource() {
        guard source == nil else { return }
        do {
            source = AsciiSource(image: try OneBoxSourceImage.make())
            sourceRevision += 1
        } catch {
            diagnostics.record(error, operation: "Prepare initial image")
            report(.decodeFailed)
        }
    }

    func importImage(from url: URL) {
        guard allowsTransientWork else { return }
        importTask?.cancel()
        importGeneration += 1
        let generation = importGeneration
        isImporting = true
        operationError = nil
        let asyncWorkOwner = asyncWorkOwner

        importTask = Task { [weak self] in
            do {
                let decoded = try await AsciiAsyncDeadline.run(
                    for: AsciiAsyncDeadline.imageImport,
                    owner: asyncWorkOwner
                ) {
                    try await AsciiImageDecoder.decode(url)
                }
                try Task.checkCancellation()
                guard let self, generation == self.importGeneration else { return }
                source = AsciiSource(image: decoded.cgImage)
                sourceRevision += 1
                isImporting = false
            } catch is CancellationError {
                guard let self, generation == self.importGeneration else { return }
                isImporting = false
            } catch let error as AsciiTimeoutError {
                guard let self, generation == self.importGeneration else { return }
                isImporting = false
                diagnostics.record(error, operation: "Import image")
                report(.importTimedOut)
            } catch let error as AsciiToolError {
                guard let self, generation == self.importGeneration else { return }
                isImporting = false
                diagnostics.record(error, operation: "Import image")
                report(error)
            } catch {
                guard let self, generation == self.importGeneration else { return }
                isImporting = false
                diagnostics.record(error, operation: "Import image")
                report(.decodeFailed)
            }
        }
    }

    func setMetalReady(_ isReady: Bool) {
        isMetalReady = isReady
        isMetalUnavailable = !isReady
    }

    func resetMetalReadiness() {
        isMetalReady = false
        isMetalUnavailable = false
    }

    func retryMetalPreparation() {
        guard isMetalUnavailable else { return }
        isMetalUnavailable = false
        metalRetryRevision &+= 1
    }

    func report(_ error: AsciiToolError) {
        if error == .metalUnavailable {
            isMetalReady = false
            isMetalUnavailable = true
        } else {
            operationError = error
        }
    }

    func clearStatus() {
        operationError = nil
    }

    func cancelTransientTasks() {
        allowsTransientWork = false
        importGeneration += 1
        importTask?.cancel()
        importTask = nil
        asyncWorkOwner.cancelAll()
        isImporting = false
    }

    /// Re-enables transient work only after the previous generation has drained.
    /// A non-cooperative framework operation keeps the session gated rather than
    /// allowing a new generation to overlap it, without blocking the view task.
    func resumeTransientTasks() async {
        guard !allowsTransientWork else { return }
        while asyncWorkOwner.activeTaskCount > 0 {
            guard !Task.isCancelled else { return }
            try? await Task.sleep(for: .milliseconds(50))
        }
        allowsTransientWork = true
    }

    func shutdown() async {
        let importTask = importTask
        cancelTransientTasks()
        if let importTask {
            await importTask.value
        }
        _ = await asyncWorkOwner.cancelAndWait(upTo: .seconds(1))
    }
}
