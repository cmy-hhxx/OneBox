import OneBoxDesignSystem
import SwiftUI

enum StockWatchToolbarAccessibility {
    static func lastRefreshValue(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .standard)
    }
}

@MainActor
struct StockWatchToolbar: View {
    let store: MonitorStore
    let isInspectorPresented: Bool
    let inspectorKeyboardFocus: FocusState<Bool>.Binding
    let inspectorAccessibilityFocus: AccessibilityFocusState<Bool>.Binding
    let addInstrument: () -> Void
    let replaceWatchlistFromJSON: () -> Void
    let refresh: () -> Void
    let toggleInspector: () -> Void

    private let watchlistPresentation: WatchlistPresentationSession
    private let quotePresentation: QuotePresentationSession
    private let diagnosticsPresentation: DiagnosticsPresentationSession

    @Environment(\.designPalette) private var palette

    init(
        store: MonitorStore,
        isInspectorPresented: Bool,
        inspectorKeyboardFocus: FocusState<Bool>.Binding,
        inspectorAccessibilityFocus: AccessibilityFocusState<Bool>.Binding,
        addInstrument: @escaping () -> Void,
        replaceWatchlistFromJSON: @escaping () -> Void,
        refresh: @escaping () -> Void,
        toggleInspector: @escaping () -> Void
    ) {
        self.store = store
        self.isInspectorPresented = isInspectorPresented
        self.inspectorKeyboardFocus = inspectorKeyboardFocus
        self.inspectorAccessibilityFocus = inspectorAccessibilityFocus
        self.addInstrument = addInstrument
        self.replaceWatchlistFromJSON = replaceWatchlistFromJSON
        self.refresh = refresh
        self.toggleInspector = toggleInspector
        self.watchlistPresentation = store.watchlistPresentation
        self.quotePresentation = store.quotePresentation
        self.diagnosticsPresentation = store.diagnosticsPresentation
    }

    private var isRefreshing: Bool {
        watchlistPresentation.instruments.contains { instrument in
            quotePresentation.snapshot.monitoredInstruments[instrument.id]?.status == .loading
        }
    }

    var body: some View {
        HStack(spacing: DesignMetrics.space8) {
            Button("添加标的", systemImage: "plus", action: addInstrument)
                .buttonStyle(ToolActionButtonStyle(kind: .primary))
                .accessibilityInputLabels(["添加标的", "搜索标的"])
                .fixedSize()

            Menu {
                Button(
                    "用 JSON 替换观察列表…",
                    systemImage: "doc.text",
                    action: replaceWatchlistFromJSON
                )
            } label: {
                Label("列表", systemImage: "ellipsis")
                    .padding(.horizontal, DesignMetrics.space8)
                    .frame(height: DesignMetrics.titlebarControlSize)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .foregroundStyle(palette.textSecondary)
            .tint(palette.textPrimary)
            .fixedSize()
            .help("更多观察列表操作")
            .accessibilityLabel("更多观察列表操作")

            Spacer(minLength: 0)

            refreshStatus

            Button("立即刷新", systemImage: "arrow.clockwise", action: refresh)
                .labelStyle(.iconOnly)
                .buttonStyle(ToolIconButtonStyle())
                .disabled(isRefreshing)
                .help(isRefreshing ? "正在刷新" : "立即刷新")
                .accessibilityLabel(isRefreshing ? "正在刷新行情" : "立即刷新行情")

            Button(
                isInspectorPresented ? "关闭检查器" : "显示检查器",
                systemImage: "sidebar.right",
                action: toggleInspector
            )
            .labelStyle(.iconOnly)
            .buttonStyle(ToolIconButtonStyle(isSelected: isInspectorPresented))
            .help(isInspectorPresented ? "关闭标的与提醒" : "显示标的与提醒")
            .accessibilityValue(isInspectorPresented ? "已打开" : "已关闭")
            .accessibilityInputLabels(["检查器", "显示检查器", "关闭检查器"])
            .focused(inspectorKeyboardFocus)
            .accessibilityFocused(inspectorAccessibilityFocus)
        }
        .font(DesignTypography.bodyMedium)
        .controlSize(.regular)
        .frame(
            maxWidth: .infinity,
            minHeight: DesignMetrics.titlebarControlSize,
            alignment: .leading
        )
    }

    @ViewBuilder
    private var refreshStatus: some View {
        if let status = MonitorStatusIndicator(
            sourceError: quotePresentation.snapshot.sourceError,
            storageError: diagnosticsPresentation.storageError
        ) {
            Image(systemName: status.icon)
                .font(DesignTypography.bodyMedium)
                .foregroundStyle(statusColor(status))
                .frame(width: DesignMetrics.space24, height: DesignMetrics.space24)
                .help("\(status.accessibilityLabel)：\(status.message)")
                .accessibilityLabel(status.accessibilityLabel)
                .accessibilityValue(status.message)
        } else if isRefreshing {
            ProgressView()
                .controlSize(.small)
                .frame(width: DesignMetrics.space24)
                .accessibilityLabel("正在刷新行情")
        } else if let lastRefresh = quotePresentation.snapshot.lastRefresh {
            ViewThatFits(in: .horizontal) {
                Label {
                    Text(lastRefresh, format: .dateTime.hour().minute().second())
                        .monospacedDigit()
                } icon: {
                    Image(systemName: "checkmark.circle")
                }
                Image(systemName: "checkmark.circle")
                    .frame(width: DesignMetrics.space24)
            }
            .font(DesignTypography.metadata)
            .foregroundStyle(palette.textSecondary)
            .lineLimit(1)
            .help(StockWatchToolbarAccessibility.lastRefreshValue(lastRefresh))
            .accessibilityLabel("最近刷新")
            .accessibilityValue(StockWatchToolbarAccessibility.lastRefreshValue(lastRefresh))
        } else {
            Image(systemName: "clock")
                .accessibilityLabel("尚未刷新")
                .help("尚未刷新")
                .font(DesignTypography.metadata)
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1)
        }
    }
    private func statusColor(_ status: MonitorStatusIndicator) -> Color {
        switch status {
        case .source:
            palette.warning
        case .storage:
            palette.negative
        }
    }

}
