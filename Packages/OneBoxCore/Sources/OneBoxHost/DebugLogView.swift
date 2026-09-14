import OneBoxDesignSystem
import OneBoxRuntime
import SwiftUI

public struct DebugLogView: View {
    @Bindable private var store: DebugLogStore
    private let catalog: ToolCatalog
    private let copyText: (String) -> Void
    private let onClose: (() -> Void)?
    @Environment(\.colorScheme) private var colorScheme
    @State private var query = ""
    @State private var selection: UUID?
    @State private var copiedText: String?
    @State private var wrapsLines = true
    public init(
        store: DebugLogStore, catalog: ToolCatalog, copyText: @escaping (String) -> Void,
        onClose: (() -> Void)? = nil
    ) {
        self.store = store
        self.catalog = catalog
        self.copyText = copyText
        self.onClose = onClose
    }

    private var palette: DesignPalette { .resolve(colorScheme) }
    private var isEmbedded: Bool { onClose != nil }
    private var filtered: [DebugLogEntry] {
        store.filtered(moduleID: store.selectedModuleID, query: query)
    }
    private var selected: DebugLogEntry? { filtered.first { $0.id == selection } }

    public var body: some View {
        VStack(spacing: 0) {
            header
            filters
            Divider().overlay(palette.border)
            if filtered.isEmpty {
                emptyState
            } else {
                HSplitView {
                    eventList
                        .frame(minWidth: 220, idealWidth: 260, maxWidth: 280)
                    eventDetail
                        .frame(minWidth: 300, maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            Divider()
            footer
        }
        .frame(minWidth: isEmbedded ? nil : 680, minHeight: isEmbedded ? 220 : 440)
        .background(palette.background)
        .foregroundStyle(palette.textPrimary)
        .tint(palette.accent)
        .environment(\.designPalette, palette)
        .onChange(of: filtered.map(\.id), initial: true) { _, ids in
            if selection == nil || !ids.contains(where: { $0 == selection }) {
                selection = ids.first
            }
        }
        .onChange(of: selection) { _, _ in copiedText = nil }
        .onExitCommand { onClose?() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("debug.logs")
    }

    @ViewBuilder private var header: some View {
        if isEmbedded {
            HStack(spacing: DesignMetrics.space12) {
                Label("调试日志", systemImage: "ladybug")
                    .font(DesignTypography.bodyMedium)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                debugModeToggle
                Button("收起调试日志", systemImage: "xmark") { onClose?() }
                    .labelStyle(.iconOnly)
                    .buttonStyle(ToolCloseButtonStyle())
                    .help("收起调试日志（⇧⌘L）")
                    .accessibilityIdentifier("debug.close")
            }
            .padding(.horizontal, DesignMetrics.space16)
            .frame(height: 44)
            .background(palette.surface)
        } else {
            standaloneHeader
        }
    }

    private var standaloneHeader: some View {
        HStack(spacing: DesignMetrics.space16) {
            Image(systemName: "ladybug")
                .font(DesignTypography.pageTitle)
                .foregroundStyle(palette.accent)
                .frame(width: 44, height: 44)
                .background(palette.selection, in: .rect(cornerRadius: 12))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DesignMetrics.space4) {
                Text("调试日志").font(DesignTypography.pageTitle)
                Text("开启后重现问题，在这里复制底层错误。")
                    .font(DesignTypography.metadata)
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer()
            debugModeToggle
        }
        .padding(DesignMetrics.space24)
        .background(palette.surface)
    }

    private var debugModeToggle: some View {
        Toggle("调试模式", isOn: $store.isEnabled)
            .font(DesignTypography.body)
            .toggleStyle(ToolSwitchStyle())
            .controlSize(.small)
            .fixedSize()
            .accessibilityIdentifier("debug.enabled")
    }

    @ViewBuilder private var filters: some View {
        if isEmbedded {
            HStack(spacing: DesignMetrics.space8) {
                modulePicker.frame(width: 384)
                searchField.frame(minWidth: 180)
                filterActions
            }
            .controlSize(.small)
            .font(DesignTypography.body)
            .padding(.horizontal, DesignMetrics.space16)
            .padding(.bottom, DesignMetrics.space8)
        } else {
            VStack(spacing: DesignMetrics.space12) {
                modulePicker
                HStack(spacing: DesignMetrics.space12) {
                    searchField
                    filterActions
                }
                .controlSize(.small)
                .font(DesignTypography.body)
            }
            .padding(.horizontal, DesignMetrics.space24)
            .padding(.vertical, DesignMetrics.space16)
        }
    }

    private var modulePicker: some View {
        ToolSegmentedPicker(
            "模块", selection: $store.selectedModuleID,
            options: [ToolSegment("全部模块", value: ToolID?.none)]
                + catalog.registrations.map {
                    ToolSegment($0.displayName, value: Optional($0.id))
                }
        )
        .accessibilityIdentifier("debug.modules")
    }

    private var searchField: some View {
        ToolTextField("搜索错误、操作或时间", text: $query, systemImage: "magnifyingglass")
            .accessibilityIdentifier("debug.search")
    }

    @ViewBuilder private var filterActions: some View {
        Button("复制筛选结果", systemImage: "doc.on.doc") {
            copy(filtered.map(\.copyText).joined(separator: "\n\n---\n\n"))
        }
        .buttonStyle(ToolActionButtonStyle(kind: .secondary, compact: isEmbedded))
        .fixedSize()
        .disabled(filtered.isEmpty)
        Button("清空", systemImage: "trash") {
            store.clear()
            selection = nil
            copiedText = nil
        }
        .buttonStyle(ToolActionButtonStyle(kind: .quiet, compact: isEmbedded))
        .fixedSize()
        .disabled(store.entries.isEmpty)
    }

    private var eventList: some View {
        List(selection: $selection) {
            ForEach(filtered) { entry in
                VStack(
                    alignment: .leading,
                    spacing: isEmbedded ? DesignMetrics.space4 : DesignMetrics.space8
                ) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(entry.moduleName).font(DesignTypography.bodyMedium)
                        Spacer(minLength: DesignMetrics.space4)
                        Text(entry.localTimeText)
                            .font(DesignTypography.metadata).monospacedDigit()
                            .foregroundStyle(
                                selection == entry.id ? palette.textPrimary : palette.textSecondary)
                    }
                    Text(entry.event.operation).font(DesignTypography.bodyMedium)
                        .lineLimit(2)
                    Text(entry.event.message.components(separatedBy: .newlines).first ?? "")
                        .font(DesignTypography.metadata)
                        .foregroundStyle(
                            selection == entry.id ? palette.textPrimary : palette.textSecondary
                        )
                        .lineLimit(1)
                }
                .padding(.vertical, isEmbedded ? DesignMetrics.space4 : DesignMetrics.space8)
                .tag(entry.id)
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .background(palette.background)
        .accessibilityIdentifier("debug.entries")
    }

    @ViewBuilder private var eventDetail: some View {
        if let selected {
            VStack(alignment: .leading, spacing: 0) {
                if isEmbedded {
                    HStack(spacing: DesignMetrics.space12) {
                        VStack(alignment: .leading, spacing: DesignMetrics.space4) {
                            HStack(spacing: DesignMetrics.space8) {
                                Text(selected.moduleName)
                                    .foregroundStyle(palette.accent)
                                Text(selected.event.operation)
                                    .textSelection(.enabled)
                            }
                            .font(DesignTypography.bodyMedium)
                            .lineLimit(1)
                            timestamp(selected)
                        }
                        Spacer(minLength: DesignMetrics.space4)
                        detailActions(selected)
                    }
                    .padding(.horizontal, DesignMetrics.space16)
                    .padding(.vertical, DesignMetrics.space8)
                } else {
                    VStack(alignment: .leading, spacing: DesignMetrics.space12) {
                        HStack {
                            Label(selected.moduleName, systemImage: moduleSymbol(selected.moduleID))
                                .font(DesignTypography.bodyMedium)
                                .foregroundStyle(palette.accent)
                            Spacer()
                            detailActions(selected)
                        }
                        Text(selected.event.operation)
                            .font(DesignTypography.sectionTitle)
                            .textSelection(.enabled)
                        timestamp(selected)
                    }
                    .padding(DesignMetrics.space16)
                }
                Divider().overlay(palette.border)
                ScrollView(wrapsLines ? .vertical : [.vertical, .horizontal]) {
                    Text(selected.event.message)
                        .font(DesignTypography.diagnostic)
                        .lineSpacing(5)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: !wrapsLines, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(DesignMetrics.space16)
                }
                .accessibilityIdentifier("debug.rawError")
            }
            .frame(maxHeight: .infinity, alignment: .topLeading)
            .background(palette.surface)
        } else {
            ContentUnavailableView("选择一条日志", systemImage: "text.alignleft")
        }
    }

    private func moduleSymbol(_ id: ToolID) -> String {
        catalog.registration(for: id)?.systemImage ?? "square.grid.2x2"
    }

    private func timestamp(_ entry: DebugLogEntry) -> some View {
        Text(entry.timestampText)
            .font(DesignTypography.metadata).monospacedDigit()
            .foregroundStyle(palette.textSecondary)
            .textSelection(.enabled)
    }

    @ViewBuilder private func detailActions(_ entry: DebugLogEntry) -> some View {
        Button("自动换行", systemImage: "text.word.spacing") { wrapsLines.toggle() }
            .labelStyle(.iconOnly)
            .buttonStyle(ToolIconButtonStyle(isSelected: wrapsLines))
            .help(wrapsLines ? "关闭自动换行" : "开启自动换行")
        Button("复制此条", systemImage: "doc.on.doc") { copy(entry.copyText) }
            .keyboardShortcut("c", modifiers: [.command, .shift])
            .buttonStyle(ToolActionButtonStyle(kind: .primary, compact: true))
            .fixedSize()
            .accessibilityIdentifier("debug.copySelected")
    }

    private var emptyTitle: String {
        !store.isEnabled && store.entries.isEmpty ? "调试模式未开启" : "暂无匹配的错误"
    }

    private var emptyDescription: String {
        !store.isEnabled && store.entries.isEmpty
            ? "开启后，重试出错的操作。日志会实时出现在这里。"
            : "当前筛选下没有错误。可以继续操作工具，或调整模块与搜索条件。"
    }

    @ViewBuilder private var emptyState: some View {
        if isEmbedded {
            HStack(spacing: DesignMetrics.space12) {
                Image(systemName: !store.isEnabled ? "ladybug" : "checkmark.circle")
                    .font(DesignTypography.pageTitle)
                    .foregroundStyle(palette.textSecondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: DesignMetrics.space4) {
                    Text(emptyTitle).font(DesignTypography.bodyMedium)
                    Text(emptyDescription)
                        .font(DesignTypography.metadata)
                        .foregroundStyle(palette.textSecondary)
                }
                if !store.isEnabled {
                    Button("开启调试模式") { store.isEnabled = true }
                        .buttonStyle(ToolActionButtonStyle(kind: .primary, compact: true))
                }
            }
            .padding(DesignMetrics.space16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            standaloneEmptyState
        }
    }

    private var standaloneEmptyState: some View {
        ContentUnavailableView {
            Label(
                emptyTitle,
                systemImage: !store.isEnabled ? "ladybug" : "checkmark.circle"
            )
        } description: {
            Text(emptyDescription)
        } actions: {
            if !store.isEnabled {
                Button("开启调试模式") { store.isEnabled = true }
                    .buttonStyle(ToolActionButtonStyle(kind: .primary))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        HStack(spacing: DesignMetrics.space12) {
            Label(
                store.isEnabled ? "实时记录中" : "已停止记录",
                systemImage: store.isEnabled ? "record.circle" : "pause.circle"
            )
            .foregroundStyle(store.isEnabled ? palette.positive : palette.textSecondary)
            Text("\(filtered.count) 条")
            if let copiedText { Text(copiedText).foregroundStyle(palette.positive) }
            Spacer()
            Text(
                store.discardedCount > 0
                    ? "已淘汰 \(store.discardedCount) 条较早记录" : "仅本次运行 · 最多 \(store.capacity) 条")
        }
        .font(DesignTypography.metadata)
        .foregroundStyle(palette.textSecondary)
        .padding(.horizontal, isEmbedded ? DesignMetrics.space16 : DesignMetrics.space24)
        .padding(.vertical, isEmbedded ? DesignMetrics.space8 : DesignMetrics.space12)
        .background(palette.surface)
    }

    private func copy(_ text: String) {
        copyText(text)
        copiedText = "已复制"
    }
}
