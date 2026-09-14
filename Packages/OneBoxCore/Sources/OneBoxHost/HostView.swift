import OneBoxDesignSystem
import OneBoxRuntime
import SwiftUI

public struct HostView: View {
    let catalog: ToolCatalog
    let onInitialContentReady: @MainActor @Sendable () -> Void
    let debugLogStore: DebugLogStore?
    @Binding private var isDiagnosticsPresented: Bool
    private let copyDiagnosticsText: (String) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selection: ToolID?
    @State private var isSidebarVisible = true
    @Environment(\.oneBoxAccessibilityReduceMotionOverride) private var reduceMotionOverride
    @State private var hasInitialContentReady = false
    @State private var performanceTrace: HostPerformanceTrace

    public init(
        catalog: ToolCatalog,
        onInitialContentReady: @escaping @MainActor @Sendable () -> Void = {},
        debugLogStore: DebugLogStore? = nil,
        isDiagnosticsPresented: Binding<Bool> = .constant(false),
        copyDiagnosticsText: @escaping (String) -> Void = { _ in }
    ) {
        self.catalog = catalog
        self.onInitialContentReady = onInitialContentReady
        self.debugLogStore = debugLogStore
        _isDiagnosticsPresented = isDiagnosticsPresented
        self.copyDiagnosticsText = copyDiagnosticsText
        let initialSelection = catalog.registrations.first?.id
        _selection = State(initialValue: initialSelection)
        _performanceTrace = State(
            initialValue: HostPerformanceTrace(initialToolID: initialSelection)
        )
    }

    public var body: some View {
        let palette = DesignPalette.resolve(colorScheme)
        VSplitView {
            workspace
                .frame(minHeight: 280)
            if isDiagnosticsPresented, let debugLogStore {
                DebugLogView(
                    store: debugLogStore, catalog: catalog,
                    copyText: copyDiagnosticsText,
                    onClose: { isDiagnosticsPresented = false }
                )
                .frame(minHeight: 220, idealHeight: 280, maxHeight: 480)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .environment(\.designPalette, palette)
        .font(DesignTypography.body)
        .tint(palette.accent)
        .background(palette.background)
    }

    private var workspace: some View {
        GeometryReader { geometry in
            let availableWidth = geometry.size.width
            let expandedSidebarWidth = min(
                DesignMetrics.sidebarWidth,
                max(
                    212,
                    availableWidth - DesignMetrics.defaultWindowSize.width
                        + DesignMetrics.sidebarWidth)
            )

            let sidebarWidth = isSidebarVisible ? expandedSidebarWidth : 60

            HStack(spacing: 0) {
                HostSidebar(
                    catalog: catalog,
                    selection: selection,
                    onSelect: activateTool,
                    onCollapse: toggleSidebar,
                    debugLogStore: debugLogStore,
                    onOpenDiagnostics: toggleDiagnostics,
                    isDiagnosticsPresented: isDiagnosticsPresented,
                    isCollapsed: !isSidebarVisible,
                    expandedWidth: expandedSidebarWidth
                )
                .frame(width: sidebarWidth)
                .padding(12)

                ToolDetailView(
                    registration: catalog.registration(for: selection),
                    onContentPresented: performanceTrace.contentDidAppear,
                    onContentReady: contentDidBecomeReady
                )
                // A definite width keeps HStack from measuring the whole tool tree at
                // zero and infinity again on every sidebar animation update.
                .frame(width: max(0, availableWidth - sidebarWidth - 24))
                .frame(maxHeight: .infinity)
                .environment(
                    \.openToolDiagnostics,
                    OpenToolDiagnosticsAction(action: showDiagnostics)
                )
            }
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(
            hasInitialContentReady ? "onebox.main.ready" : "onebox.main.loading"
        )
    }

    private func showDiagnostics() {
        guard let debugLogStore else { return }
        debugLogStore.selectedModuleID = selection
        isDiagnosticsPresented = true
    }

    private func toggleDiagnostics() {
        if isDiagnosticsPresented {
            isDiagnosticsPresented = false
        } else {
            showDiagnostics()
        }
    }

    private func activateTool(_ toolID: ToolID) {
        guard selection != toolID else { return }
        performanceTrace.beginActivation(for: toolID)
        selection = toolID
    }

    private func toggleSidebar() {
        let reducesMotion = reduceMotionOverride ?? reduceMotion
        var transaction = Transaction(animation: reducesMotion ? nil : DesignMotion.sidebar)
        transaction.disablesAnimations = reducesMotion
        withTransaction(transaction) { isSidebarVisible.toggle() }
    }

    private func contentDidBecomeReady(for toolID: ToolID) {
        guard performanceTrace.contentDidBecomeReady(for: toolID) else { return }
        guard !hasInitialContentReady else { return }
        hasInitialContentReady = true
        onInitialContentReady()
    }
}

#Preview("Light") {
    HostView(catalog: .preview)
        .frame(width: 1048, height: 648)
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    HostView(catalog: .preview)
        .frame(width: 1048, height: 648)
        .preferredColorScheme(.dark)
}

extension ToolCatalog {
    fileprivate static let preview = ToolCatalog(registrations: [
        ToolRegistration(
            id: ToolID(rawValue: "preview"),
            displayName: "预览工具"
        ) {
            Text("预览内容")
        }
    ])
}
