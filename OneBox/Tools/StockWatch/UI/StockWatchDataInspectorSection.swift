import Accessibility
import OneBoxDesignSystem
import SwiftUI

@MainActor
struct StockWatchDataInspectorSection: View {
    @ObservedObject var store: MonitorStore
    @Bindable var preferences: StockWatchPreferences
    let copyText: (String) -> Bool
    let revealDirectory: (URL) -> Bool

    @Environment(\.designPalette) private var palette
    @State private var databasePathActionMessage: String?
    @State private var isRefreshingData = false
    @State private var isConfirmingCacheClear = false

    var body: some View {
        VStack(alignment: .leading, spacing: DesignMetrics.space12) {
            Text("数据")
                .font(DesignTypography.sectionTitle)
                .accessibilityAddTraits(.isHeader)

            VStack(alignment: .leading, spacing: DesignMetrics.space4) {
                Text("刷新间隔")
                    .font(DesignTypography.metadata)
                    .foregroundStyle(palette.textSecondary)
                Picker("刷新间隔", selection: $preferences.refreshInterval) {
                    Text("15 秒").tag(15)
                    Text("30 秒").tag(30)
                    Text("60 秒").tag(60)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityLabel("刷新间隔")
            }

            dataRow(
                title: "数据提供方",
                value: "腾讯分时 · 东方财富备用",
                systemImage: "antenna.radiowaves.left.and.right"
            )
            dataRow(
                title: "最近刷新",
                value: lastRefreshText,
                systemImage: "clock"
            )
            dataRow(
                title: "缓存分钟数",
                value: "\(store.quoteBarCount.formatted()) 分钟",
                systemImage: "clock.arrow.circlepath"
            )

            Button(action: refreshData) {
                if isRefreshingData {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Label("刷新行情与诊断", systemImage: "arrow.clockwise")
                }
            }
            .buttonStyle(.bordered)
            .disabled(isRefreshingData)

            databasePath

            Button("清空行情缓存…", systemImage: "trash", role: .destructive) {
                isConfirmingCacheClear = true
            }
            .buttonStyle(.bordered)
        }
        .task {
            await store.refreshQuoteBarCount()
        }
        .confirmationDialog(
            "清空全部行情缓存？",
            isPresented: $isConfirmingCacheClear,
            titleVisibility: .visible
        ) {
            Button("清空行情缓存", role: .destructive, action: clearQuoteHistory)
            Button("取消", role: .cancel) {}
        } message: {
            Text("所有本地行情分钟数据都会被删除。观察列表会保留，此操作不可撤销。")
        }
    }

    private var databasePath: some View {
        VStack(alignment: .leading, spacing: DesignMetrics.space4) {
            Label("数据库路径", systemImage: "externaldrive")
                .font(DesignTypography.metadata)

            Text(store.databasePath.isEmpty ? "未打开" : store.databasePath)
                .font(DesignTypography.metadata)
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel("数据库路径")
                .accessibilityValue(store.databasePath)

            HStack(spacing: DesignMetrics.space8) {
                Button("复制路径", systemImage: "doc.on.doc", action: copyDatabasePath)
                Button("显示目录", systemImage: "folder", action: revealDatabaseDirectory)
            }
            .buttonStyle(.bordered)
            .disabled(store.databasePath.isEmpty)

            if let databasePathActionMessage {
                Text(databasePathActionMessage)
                    .font(DesignTypography.metadata)
                    .foregroundStyle(
                        databasePathActionMessage.hasPrefix("已")
                            ? palette.positive
                            : palette.negative
                    )
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
    }

    private func dataRow(
        title: String,
        value: String,
        systemImage: String
    ) -> some View {
        VStack(alignment: .leading, spacing: DesignMetrics.space4) {
            Label(title, systemImage: systemImage)
                .font(DesignTypography.metadata)
            Text(value)
                .font(DesignTypography.metadata)
                .monospacedDigit()
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var lastRefreshText: String {
        guard let lastRefresh = store.lastRefresh else { return tr("尚未刷新") }
        return lastRefresh.formatted(date: .abbreviated, time: .shortened)
    }

    private func refreshData() {
        guard !isRefreshingData else { return }
        isRefreshingData = true
        Task {
            await store.refreshAll()
            await store.refreshQuoteBarCount()
            isRefreshingData = false
        }
    }

    private func copyDatabasePath() {
        guard !store.databasePath.isEmpty else { return }
        let succeeded = copyText(store.databasePath)
        publishDatabasePathFeedback(succeeded ? "已复制数据库路径" : "复制数据库路径失败")
    }

    private func revealDatabaseDirectory() {
        guard !store.databasePath.isEmpty else { return }
        let directory = URL(fileURLWithPath: store.databasePath).deletingLastPathComponent()
        let succeeded = revealDirectory(directory)
        publishDatabasePathFeedback(succeeded ? "已在 Finder 中显示目录" : "无法在 Finder 中显示目录")
    }

    private func publishDatabasePathFeedback(_ message: String) {
        databasePathActionMessage = message
        if !message.hasPrefix("已") {
            AccessibilityNotification.Announcement(message).post()
        }
    }

    private func clearQuoteHistory() {
        Task {
            await store.clearQuoteHistory()
            await store.refreshQuoteBarCount()
        }
    }
}
