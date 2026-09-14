import Accessibility
import OneBoxDesignSystem
import SwiftUI

@MainActor
struct StockWatchDataInspectorSection: View {
    let store: MonitorStore
    @Bindable var preferences: StockWatchPreferences
    let copyText: (String) -> Bool
    let revealDirectory: (URL) -> Bool

    private let quotePresentation: QuotePresentationSession
    private let diagnosticsPresentation: DiagnosticsPresentationSession

    @Environment(\.designPalette) private var palette
    @State private var databasePathActionMessage: String?
    @State private var isRefreshingData = false
    @State private var isConfirmingCacheClear = false

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
        self.quotePresentation = store.quotePresentation
        self.diagnosticsPresentation = store.diagnosticsPresentation
    }

    var body: some View {
        InspectorSection(title: "行情数据") {
            VStack(alignment: .leading, spacing: DesignMetrics.space4) {
                Text("刷新间隔")
                    .font(DesignTypography.metadata)
                    .foregroundStyle(palette.textSecondary)
                ToolSegmentedPicker(
                    "刷新间隔",
                    selection: $preferences.refreshInterval,
                    options: [
                        ToolSegment("15 秒", value: 15),
                        ToolSegment("30 秒", value: 30),
                        ToolSegment("60 秒", value: 60),
                    ]
                )
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
            Button(action: refreshData) {
                if isRefreshingData {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Label("刷新行情与诊断", systemImage: "arrow.clockwise")
                }
            }
            .buttonStyle(ToolActionButtonStyle(kind: .secondary, compact: true))
            .disabled(isRefreshingData)

            DisclosureGroup("本地缓存与存储") {
                VStack(alignment: .leading, spacing: DesignMetrics.space12) {
                    Text("已缓存 \(diagnosticsPresentation.quoteBarCount.formatted()) 分钟行情")
                        .font(DesignTypography.metadata)
                        .foregroundStyle(palette.textSecondary)
                    databasePath
                    Button("清空行情缓存…", systemImage: "trash", role: .destructive) {
                        isConfirmingCacheClear = true
                    }
                    .buttonStyle(ToolActionButtonStyle(kind: .quiet, compact: true))
                }
                .padding(.top, DesignMetrics.space8)
            }
            .font(DesignTypography.metadata)
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

            Text(databasePathValue.isEmpty ? "未打开" : databasePathValue)
                .font(DesignTypography.metadata)
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel("数据库路径")
                .accessibilityValue(databasePathValue)

            VStack(alignment: .leading, spacing: DesignMetrics.space4) {
                Button("复制路径", systemImage: "doc.on.doc", action: copyDatabasePath)
                Button("显示目录", systemImage: "folder", action: revealDatabaseDirectory)
            }
            .buttonStyle(ToolActionButtonStyle(kind: .quiet, compact: true))
            .disabled(databasePathValue.isEmpty)

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
        guard let lastRefresh = quotePresentation.snapshot.lastRefresh else {
            return tr("尚未刷新")
        }
        return lastRefresh.formatted(
            Date.FormatStyle(date: .numeric, time: .shortened, locale: Locale(identifier: "zh_CN"))
        )
    }

    private var databasePathValue: String {
        diagnosticsPresentation.databasePath
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
        guard !databasePathValue.isEmpty else { return }
        let succeeded = copyText(databasePathValue)
        publishDatabasePathFeedback(succeeded ? "已复制数据库路径" : "复制数据库路径失败")
    }

    private func revealDatabaseDirectory() {
        guard !databasePathValue.isEmpty else { return }
        let directory = URL(fileURLWithPath: databasePathValue).deletingLastPathComponent()
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
