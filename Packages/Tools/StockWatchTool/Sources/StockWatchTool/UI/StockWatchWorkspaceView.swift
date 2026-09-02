import OneBoxDesignSystem
import SwiftUI

@MainActor
struct StockWatchWorkspaceView: View {
    @ObservedObject var store: MonitorStore
    let preferences: StockWatchPreferences
    let copyText: (String) -> Bool
    let revealDirectory: (URL) -> Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedInstrumentID: InstrumentID?
    @State private var isInspectorPresented = true
    @State private var isAddInstrumentPresented = false
    @State private var isJSONSheetPresented = false
    @State private var focusRestorationTask: Task<Void, Never>?
    @AccessibilityFocusState private var isInspectorButtonFocused: Bool

    var body: some View {
        VStack(spacing: DesignMetrics.space8) {
            StockWatchToolbar(
                store: store,
                isInspectorPresented: isInspectorPresented,
                inspectorFocus: $isInspectorButtonFocused,
                addInstrument: { isAddInstrumentPresented = true },
                replaceWatchlistFromJSON: { isJSONSheetPresented = true },
                refresh: refresh,
                toggleInspector: toggleInspector
            )

            workspaceContent
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .sheet(isPresented: $isAddInstrumentPresented) {
            AddInstrumentSheet(store: store) { instrument in
                selectedInstrumentID = instrument.id
            }
        }
        .sheet(isPresented: $isJSONSheetPresented) {
            WatchlistJSONSheet(store: store, copyText: copyText) {
                selectedInstrumentID = store.instruments.first?.id
            }
        }
        .onAppear(perform: reconcileSelection)
        .onChange(of: store.instruments) { _, _ in
            reconcileSelection()
        }
        .onExitCommand(perform: closeInspector)
        .onDisappear {
            focusRestorationTask?.cancel()
            focusRestorationTask = nil
        }
    }

    private var workspaceContent: some View {
        ZStack(alignment: .topTrailing) {
            HStack(spacing: DesignMetrics.space12) {
                monitor

                if isInspectorPresented {
                    inspector
                        .frame(width: DesignMetrics.inspectorWidth)
                        .transition(inspectorTransition)
                }
            }

            if let alert = store.activeAlert {
                AlertBannerView(
                    alert: alert,
                    setDismissalPaused: store.setAlertDismissalPaused,
                    dismiss: store.dismissActiveAlert
                )
                .padding(DesignMetrics.space12)
                .transition(
                    reduceMotion
                        ? .opacity
                        : .move(edge: .top).combined(with: .opacity)
                )
                .zIndex(1)
            }
        }
        .animation(
            reduceMotion ? .easeInOut(duration: 0.12) : .easeOut(duration: 0.18),
            value: store.activeAlert?.id
        )
    }

    private var monitor: some View {
        MarketMonitorView(
            store: store,
            selectedInstrumentID: $selectedInstrumentID,
            openAddInstrument: { isAddInstrumentPresented = true }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var inspector: some View {
        StockWatchInspector(
            store: store,
            preferences: preferences,
            selectedInstrumentID: selectedInstrumentID,
            copyText: copyText,
            revealDirectory: revealDirectory,
            close: closeInspector
        )
    }

    private var inspectorTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .move(edge: .trailing).combined(with: .opacity)
    }

    private func refresh() {
        Task {
            await store.refreshAll()
        }
    }

    private func toggleInspector() {
        if isInspectorPresented {
            closeInspector()
            return
        }
        focusRestorationTask?.cancel()
        focusRestorationTask = nil
        isInspectorButtonFocused = false
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
            isInspectorPresented = true
        }
    }

    private func closeInspector() {
        guard isInspectorPresented else { return }
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
            isInspectorPresented = false
        }
        restoreInspectorButtonFocus()
    }

    private func restoreInspectorButtonFocus() {
        focusRestorationTask?.cancel()
        focusRestorationTask = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled else { return }
            isInspectorButtonFocused = true
            focusRestorationTask = nil
        }
    }

    private func reconcileSelection() {
        if let selectedInstrumentID,
            store.instruments.contains(where: { $0.id == selectedInstrumentID })
        {
            return
        }
        selectedInstrumentID = store.instruments.first?.id
    }
}
