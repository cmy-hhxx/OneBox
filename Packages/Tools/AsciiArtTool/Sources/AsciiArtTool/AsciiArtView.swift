import OneBoxDesignSystem
import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct AsciiArtView: View {
    @Bindable var session: AsciiSession
    let renderCache: AsciiRenderCache

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var isImporterPresented = false
    @State private var isExporterPresented = false
    @State private var exportDocument = PNGDocument()
    @State private var exportTask: Task<Void, Never>?
    @State private var transientResumeTask: Task<Void, Never>?
    @State private var focusRestorationTask: Task<Void, Never>?
    @State private var isExporting = false
    @AccessibilityFocusState private var isParameterButtonFocused: Bool

    var body: some View {
        VStack(spacing: DesignMetrics.space8) {
            AsciiToolbar(
                session: session,
                isExporting: isExporting,
                parameterFocus: $isParameterButtonFocused,
                open: presentImporter,
                toggleParameters: toggleParameters,
                export: beginExport
            )

            HStack(spacing: DesignMetrics.space12) {
                AsciiCanvasView(session: session, renderCache: renderCache)

                if session.isInspectorPresented {
                    AsciiInspector(session: session, close: closeInspector)
                        .frame(width: 248)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
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
        .onExitCommand(perform: closeInspector)
    }

    private func appear() {
        session.prepareInitialSource()
        session.setReduceMotion(reduceMotion)
        session.setSceneActive(scenePhase == .active)
        session.setVisible(true)
        transientResumeTask?.cancel()
        transientResumeTask = Task { @MainActor in
            await session.resumeTransientTasks()
            transientResumeTask = nil
        }
    }

    private func disappear() {
        session.setVisible(false)
        session.cancelTransientTasks()
        transientResumeTask?.cancel()
        transientResumeTask = nil
        exportTask?.cancel()
        exportTask = nil
        focusRestorationTask?.cancel()
        focusRestorationTask = nil
        isExporting = false
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
                session.report(.exportFailed)
            }
            exportTask = nil
        }
    }

    private func completeExport(_ result: Result<URL, Error>) {
        if case .failure(let error) = result,
            (error as? CocoaError)?.code != .userCancelled
        {
            session.report(.exportFailed)
        }
    }

    private func closeInspector() {
        guard session.isInspectorPresented else { return }
        session.isInspectorPresented = false
        restoreParameterFocus()
    }

    private func toggleParameters() {
        if session.isInspectorPresented {
            closeInspector()
            return
        }
        focusRestorationTask?.cancel()
        focusRestorationTask = nil
        isParameterButtonFocused = false
        session.isInspectorPresented.toggle()
    }

    private func restoreParameterFocus() {
        focusRestorationTask?.cancel()
        focusRestorationTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(100))
                isParameterButtonFocused = true
            } catch {
                return
            }
            focusRestorationTask = nil
        }
    }
}
