import Foundation
import Observation

@MainActor
@Observable
final class AsciiSession {
    var settings = AsciiSettings()
    var transform = CanvasTransform()
    var isInspectorPresented = true
    private(set) var source: AsciiSource?
    private(set) var sourceRevision = 0
    private(set) var isImporting = false
    private(set) var isMetalReady = false

    private var isVisible = false
    private var isWindowActive = true
    private var reduceMotion = false
    private var wantsPlayback = true
    private var manuallyEnabledWithReduceMotion = false
    private var importGeneration = 0
    private var operationError: AsciiToolError?
    private var isMetalUnavailable = false
    @ObservationIgnored private var importTask: Task<Void, Never>?

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
        isVisible && isWindowActive && settings.animation != .off && wantsPlayback
            && (!reduceMotion || manuallyEnabledWithReduceMotion)
    }

    func setVisible(_ isVisible: Bool) {
        self.isVisible = isVisible
    }

    func setWindowActive(_ isWindowActive: Bool) {
        self.isWindowActive = isWindowActive
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
            source = AsciiSource(
                image: try OneBoxSourceImage.make(),
                name: "OneBox",
                isBuiltIn: true
            )
            sourceRevision += 1
        } catch {
            report(.decodeFailed)
        }
    }

    func importImage(from url: URL) {
        importTask?.cancel()
        importGeneration += 1
        let generation = importGeneration
        isImporting = true
        operationError = nil

        importTask = Task { [weak self] in
            do {
                let decoded = try await AsciiAsyncDeadline.run(
                    for: AsciiAsyncDeadline.imageImport
                ) {
                    try await AsciiImageDecoder.decode(url)
                }
                try Task.checkCancellation()
                guard let self, generation == self.importGeneration else { return }
                source = AsciiSource(
                    image: decoded.cgImage,
                    name: decoded.sourceName,
                    isBuiltIn: false
                )
                sourceRevision += 1
                isImporting = false
            } catch is CancellationError {
                guard let self, generation == self.importGeneration else { return }
                isImporting = false
            } catch let error as AsciiToolError {
                guard let self, generation == self.importGeneration else { return }
                isImporting = false
                report(error)
            } catch {
                guard let self, generation == self.importGeneration else { return }
                isImporting = false
                report(.decodeFailed)
            }
        }
    }

    func setMetalReady(_ isReady: Bool) {
        isMetalReady = isReady
        isMetalUnavailable = !isReady
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
        importGeneration += 1
        importTask?.cancel()
        importTask = nil
        isImporting = false
    }
}
