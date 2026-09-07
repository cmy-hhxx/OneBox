import OneBoxDesignSystem
import SwiftUI

@MainActor
struct StockWatchWorkspaceView: View {
    let store: MonitorStore
    let preferences: StockWatchPreferences
    let copyText: (String) -> Bool
    let revealDirectory: (URL) -> Bool

    private let watchlistPresentation: WatchlistPresentationSession
    private let alertPresentation: AlertPresentationSession

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedInstrumentID: InstrumentID?
    @State private var isInspectorPresented = false
    @State private var isAddInstrumentPresented = false
    @State private var isJSONSheetPresented = false
    @State private var focusRestorationTask: Task<Void, Never>?
    @FocusState private var isInspectorButtonKeyboardFocused: Bool
    @AccessibilityFocusState private var isInspectorButtonAccessibilityFocused: Bool

    init(
        store: MonitorStore,
        preferences: StockWatchPreferences,
        copyText: @escaping (String) -> Bool,
        revealDirectory: @escaping (URL) -> Bool
    ) {
        self.store = store
        self.preferences = preferences
        self.copyText = copyText
        self.revealDirectory = revealDirectory
        self.watchlistPresentation = store.watchlistPresentation
        self.alertPresentation = store.alertPresentation
    }

    var body: some View {
        VStack(spacing: DesignMetrics.space8) {
            StockWatchToolbar(
                store: store,
                isInspectorPresented: isInspectorPresented,
                inspectorKeyboardFocus: $isInspectorButtonKeyboardFocused,
                inspectorAccessibilityFocus: $isInspectorButtonAccessibilityFocused,
                addInstrument: { isAddInstrumentPresented = true },
                replaceWatchlistFromJSON: { isJSONSheetPresented = true },
                refresh: refresh,
                toggleInspector: toggleInspector
            )

            workspaceContent
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .toolInspector(
            isPresented: $isInspectorPresented,
            title: "检查器",
            closeLabel: "关闭检查器",
            onDismiss: restoreInspectorButtonFocus
        ) {
            StockWatchInspector(
                store: store,
                preferences: preferences,
                selectedInstrumentID: selectedInstrumentID,
                copyText: copyText,
                revealDirectory: revealDirectory
            )
        }
        .sheet(isPresented: $isAddInstrumentPresented) {
            AddInstrumentSheet(store: store) { instrument in
                selectedInstrumentID = instrument.id
            }
        }
        .sheet(isPresented: $isJSONSheetPresented) {
            WatchlistJSONSheet(store: store, copyText: copyText) {
                selectedInstrumentID = watchlistPresentation.instruments.first?.id
            }
        }
        .onAppear(perform: reconcileSelection)
        .onChange(of: watchlistPresentation.instruments) { _, _ in
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
            monitor

            if let alert = alertPresentation.activeAlert {
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
            value: alertPresentation.activeAlert?.id
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
        isInspectorButtonKeyboardFocused = false
        isInspectorButtonAccessibilityFocused = false
        isInspectorPresented = true
    }

    private func closeInspector() {
        guard isInspectorPresented else { return }
        isInspectorPresented = false
    }

    private func restoreInspectorButtonFocus() {
        focusRestorationTask?.cancel()
        focusRestorationTask = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled, !isInspectorPresented else { return }
            isInspectorButtonKeyboardFocused = true
            isInspectorButtonAccessibilityFocused = true
            focusRestorationTask = nil
        }
    }

    private func reconcileSelection() {
        if let selectedInstrumentID,
            watchlistPresentation.instruments.contains(where: { $0.id == selectedInstrumentID })
        {
            return
        }
        selectedInstrumentID = watchlistPresentation.instruments.first?.id
    }
}
