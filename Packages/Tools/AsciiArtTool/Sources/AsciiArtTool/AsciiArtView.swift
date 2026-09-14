import OSLog
import OneBoxDesignSystem
import OneBoxRuntime
import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct AsciiArtView: View {
    private static let exportSignposter = OSSignposter(
        subsystem: "com.cmy.OneBox",
        category: "ASCII"
    )

    @Bindable var session: AsciiSession
    let renderCache: AsciiRenderCache

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.toolContentReadinessReporter) private var contentReadinessReporter
    @State private var firstContentTrace = AsciiFirstContentPerformanceTrace()
    @State private var isImporterPresented = false
    @State private var isExporterPresented = false
    @State private var exportDocument = PNGDocument()
    @State private var exportTask: Task<Void, Never>?
    @State private var transientResumeTask: Task<Void, Never>?
    @State private var focusRestorationTask: Task<Void, Never>?
    @State private var isExporting = false
    @FocusState private var isParameterButtonKeyboardFocused: Bool
    @AccessibilityFocusState private var isParameterButtonAccessibilityFocused: Bool

    var body: some View {
        VStack(spacing: DesignMetrics.space16) {
            AsciiToolbar(
                session: session,
                isExporting: isExporting,
                parameterKeyboardFocus: $isParameterButtonKeyboardFocused,
                parameterAccessibilityFocus: $isParameterButtonAccessibilityFocused,
                open: presentImporter,
                toggleParameters: toggleParameters,
                export: beginExport
            )

            AsciiCanvasView(session: session, renderCache: renderCache)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ascii.workspace")
        .toolInspector(
            isPresented: $session.isInspectorPresented,
            title: "参数",
            closeLabel: "关闭参数",
            onDismiss: restoreParameterFocus
        ) {
            AsciiInspector(session: session)
        }
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [.png, .jpeg, .svg],
            allowsMultipleSelection: false,
            onCompletion: completeImport
        )
        .fileExporter(
            isPresented: $isExporterPresented,
            document: exportDocument,
            contentType: .png,
            defaultFilename: "OneBox-ASCII",
            onCompletion: completeExport
        )
        .onAppear(perform: appear)
        .onDisappear(perform: disappear)
        .onChange(of: reduceMotion) { _, value in
            session.setReduceMotion(value)
        }
        .onChange(of: scenePhase) { _, phase in
            session.setSceneActive(phase == .active)
        }
        .onChange(of: firstContentResolved, initial: true) { _, isResolved in
            guard isResolved else { return }
            reportFirstContentReady()
        }
        .onExitCommand(perform: closeInspector)
    }

    private func appear() {
        firstContentTrace.begin()
        session.prepareInitialSource()
        session.setReduceMotion(reduceMotion)
        session.setSceneActive(scenePhase == .active)
        session.setVisible(true)
        if firstContentResolved {
            reportFirstContentReady()
        }
        transientResumeTask?.cancel()
        transientResumeTask = Task { @MainActor in
            await session.resumeTransientTasks()
            transientResumeTask = nil
        }
    }

    private func disappear() {
        firstContentTrace.cancel()
        session.setVisible(false)
        session.resetMetalReadiness()
        session.cancelTransientTasks()
        transientResumeTask?.cancel()
        transientResumeTask = nil
        exportTask?.cancel()
        exportTask = nil
        focusRestorationTask?.cancel()
        focusRestorationTask = nil
        isExporting = false
    }

    private var firstContentResolved: Bool {
        guard session.source != nil else { return false }
        return session.isMetalReady || session.statusError == .metalUnavailable
    }

    private func reportFirstContentReady() {
        guard firstContentTrace.finish() else { return }
        contentReadinessReporter.reportFirstContentReady()
    }

    private func presentImporter() {
        isImporterPresented = true
    }

    private func completeImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            if let url = urls.first {
                session.importImage(from: url)
            }
        case .failure(let error):
            if (error as? CocoaError)?.code != .userCancelled {
                session.diagnostics.record(error, operation: "Open image file")
                session.report(.decodeFailed)
            }
        }
    }

    private func beginExport() {
        guard session.isMetalReady, let source = session.source,
            let snapshot = session.renderSnapshot
        else { return }
        exportTask?.cancel()
        isExporting = true
        session.clearStatus()
        exportTask = Task { @MainActor in
            let interval = Self.exportSignposter.beginInterval("Export")
            defer { Self.exportSignposter.endInterval("Export", interval) }
            do {
                let data = try await AsciiAsyncDeadline.run(
                    for: AsciiAsyncDeadline.pngExport,
                    owner: session.asyncWorkOwner
                ) {
                    try await AsciiPNGExporter.render(
                        cache: renderCache,
                        source: source,
                        snapshot: snapshot
                    )
                }
                try Task.checkCancellation()
                exportDocument = PNGDocument(data: data)
                isExporting = false
                isExporterPresented = true
            } catch is CancellationError {
                isExporting = false
            } catch {
                isExporting = false
                session.diagnostics.record(error, operation: "Render PNG")
                session.report(.exportFailed)
            }
            exportTask = nil
        }
    }

    private func completeExport(_ result: Result<URL, Error>) {
        if case .failure(let error) = result,
            (error as? CocoaError)?.code != .userCancelled
        {
            session.diagnostics.record(error, operation: "Save PNG")
            session.report(.exportFailed)
        }
    }

    private func closeInspector() {
        guard session.isInspectorPresented else { return }
        session.isInspectorPresented = false
    }

    private func toggleParameters() {
        if session.isInspectorPresented {
            closeInspector()
            return
        }
        focusRestorationTask?.cancel()
        focusRestorationTask = nil
        isParameterButtonKeyboardFocused = false
        isParameterButtonAccessibilityFocused = false
        session.isInspectorPresented = true
    }

    private func restoreParameterFocus() {
        focusRestorationTask?.cancel()
        focusRestorationTask = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled, !session.isInspectorPresented else { return }
            isParameterButtonKeyboardFocused = true
            isParameterButtonAccessibilityFocused = true
            focusRestorationTask = nil
        }
    }
}
