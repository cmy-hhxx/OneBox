import OneBoxDesignSystem
import SwiftUI

enum StockWatchToolbarAccessibility {
    static func lastRefreshValue(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .standard)
    }
}

@MainActor
struct StockWatchToolbar: View {
    @ObservedObject var store: MonitorStore
    let isInspectorPresented: Bool
    let inspectorFocus: AccessibilityFocusState<Bool>.Binding
    let addInstrument: () -> Void
    let replaceWatchlistFromJSON: () -> Void
    let refresh: () -> Void
    let toggleInspector: () -> Void

    @Environment(\.designPalette) private var palette

    private var isRefreshing: Bool {
        store.instruments.contains { instrument in
            store.monitoredInstrument(for: instrument.id)?.status == .loading
        }
    }

    var body: some View {
        HStack(spacing: DesignMetrics.space8) {
            Button("添加标的", systemImage: "plus", action: addInstrument)
                .buttonStyle(.borderedProminent)
                .tint(palette.accent)
                .keyboardShortcut("n", modifiers: .command)
                .accessibilityInputLabels(["添加标的", "搜索标的"])

            Menu {
                Button(
                    "用 JSON 替换观察列表…",
                    systemImage: "doc.text",
                    action: replaceWatchlistFromJSON
                )
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: DesignMetrics.space16, height: DesignMetrics.space16)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: DesignMetrics.titlebarControlSize)
            .help("更多观察列表操作")
            .accessibilityLabel("更多观察列表操作")

            Spacer(minLength: 0)

            refreshStatus

            Button("立即刷新", systemImage: "arrow.clockwise", action: refresh)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .frame(width: DesignMetrics.titlebarControlSize)
                .foregroundStyle(palette.textPrimary)
                .disabled(isRefreshing)
                .help(isRefreshing ? "正在刷新" : "立即刷新")
                .accessibilityLabel(isRefreshing ? "正在刷新行情" : "立即刷新行情")

            Button(
                isInspectorPresented ? "关闭检查器" : "显示检查器",
                systemImage: "sidebar.right",
                action: toggleInspector
            )
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .frame(width: DesignMetrics.titlebarControlSize)
            .foregroundStyle(palette.textPrimary)
            .help(isInspectorPresented ? "关闭检查器" : "显示检查器")
            .accessibilityValue(isInspectorPresented ? "已打开" : "已关闭")
            .accessibilityInputLabels(["检查器", "显示检查器", "关闭检查器"])
            .accessibilityFocused(inspectorFocus)
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
            sourceError: store.sourceError,
            storageError: store.storageError
        ) {
            Label(status.accessibilityLabel, systemImage: status.icon)
                .font(DesignTypography.metadata)
                .foregroundStyle(statusColor(status))
                .lineLimit(1)
                .help(status.message)
        } else if isRefreshing {
            HStack(spacing: DesignMetrics.space4) {
                ProgressView()
                    .controlSize(.small)
                Text("正在刷新")
                    .font(DesignTypography.metadata)
                    .foregroundStyle(palette.textSecondary)
            }
            .accessibilityElement(children: .combine)
        } else if let lastRefresh = store.lastRefresh {
            Label {
                Text(lastRefresh, style: .relative)
                    .monospacedDigit()
            } icon: {
                Image(systemName: "checkmark.circle")
            }
            .font(DesignTypography.metadata)
            .foregroundStyle(palette.textSecondary)
            .lineLimit(1)
            .help(StockWatchToolbarAccessibility.lastRefreshValue(lastRefresh))
            .accessibilityLabel("最近刷新")
            .accessibilityValue(StockWatchToolbarAccessibility.lastRefreshValue(lastRefresh))
        } else {
            Label("尚未刷新", systemImage: "clock")
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
