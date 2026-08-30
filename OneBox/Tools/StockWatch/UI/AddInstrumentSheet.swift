import OneBoxDesignSystem
import SwiftUI

enum AddInstrumentAccessibility {
    static func resultActionLabel(for instrument: Instrument, isAdded: Bool) -> String {
        let action = isAdded ? tr("已添加") : tr("添加")
        return
            "\(action) \(instrument.name)，\(instrument.symbol)，\(instrument.namespace.displayName)"
    }
}

@MainActor
struct AddInstrumentSheet: View {
    @ObservedObject private var store: MonitorStore
    @StateObject private var searchModel: WatchlistSearchModel
    let onAdded: (Instrument) -> Void

    @Environment(\.designPalette) private var palette
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isSearchFieldFocused: Bool
    @State private var feedbackMessage: String?

    init(store: MonitorStore, onAdded: @escaping (Instrument) -> Void) {
        _store = ObservedObject(wrappedValue: store)
        _searchModel = StateObject(
            wrappedValue: WatchlistSearchModel { query in
                try await store.search(query)
            }
        )
        self.onAdded = onAdded
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignMetrics.space16) {
            header
            searchControls
            searchContent
        }
        .padding(DesignMetrics.space16)
        .frame(width: 420, height: 430, alignment: .topLeading)
        .background(palette.background)
        .onAppear {
            isSearchFieldFocused = true
        }
        .onChange(of: searchModel.query) { _, _ in
            feedbackMessage = nil
        }
        .onDisappear {
            searchModel.cancel()
        }
    }

    private var header: some View {
        HStack {
            Text("添加标的")
                .font(DesignTypography.sectionTitle)
                .foregroundStyle(palette.textPrimary)

            Spacer(minLength: 0)

            Button("关闭", systemImage: "xmark") {
                dismiss()
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .frame(width: DesignMetrics.space24, height: DesignMetrics.space24)
            .accessibilityLabel("关闭添加标的")
        }
    }

    private var searchControls: some View {
        VStack(alignment: .leading, spacing: DesignMetrics.space8) {
            HStack(spacing: DesignMetrics.space8) {
                TextField("名称或代码", text: $searchModel.query)
                    .textFieldStyle(.roundedBorder)
                    .font(DesignTypography.body)
                    .focused($isSearchFieldFocused)
                    .onSubmit(searchModel.submit)
                    .accessibilityLabel("搜索名称或代码")

                Button("搜索", systemImage: "magnifyingglass", action: searchModel.submit)
                    .buttonStyle(.borderedProminent)
                    .tint(palette.accent)
                    .disabled(cleanQuery.isEmpty || searchModel.isSearching)
            }

            if searchModel.isSearching {
                HStack(spacing: DesignMetrics.space8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("正在搜索支持的 A股、港股和美股…")
                        .font(DesignTypography.metadata)
                        .foregroundStyle(palette.textSecondary)
                    Spacer(minLength: 0)
                    Button("取消搜索", action: searchModel.cancel)
                        .buttonStyle(.borderless)
                        .font(DesignTypography.bodyMedium)
                }
            } else {
                Text("输入公司名称或交易代码后按 Return。")
                    .font(DesignTypography.metadata)
                    .foregroundStyle(palette.textSecondary)
            }
        }
    }

    @ViewBuilder
    private var searchContent: some View {
        if searchModel.results.isEmpty {
            VStack(spacing: DesignMetrics.space8) {
                Image(systemName: searchStatusIcon)
                    .font(DesignTypography.sectionTitle)
                    .foregroundStyle(
                        searchModel.hasSearchFailure ? palette.negative : palette.textSecondary
                    )
                    .accessibilityHidden(true)

                Text(searchStatusTitle)
                    .font(DesignTypography.bodyMedium)
                    .foregroundStyle(palette.textPrimary)

                Text(searchStatusMessage)
                    .font(DesignTypography.metadata)
                    .foregroundStyle(
                        searchModel.hasSearchFailure ? palette.negative : palette.textSecondary
                    )
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                if searchModel.hasSearchFailure {
                    Button("重试", systemImage: "arrow.clockwise", action: searchModel.submit)
                        .buttonStyle(.bordered)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(alignment: .leading, spacing: DesignMetrics.space8) {
                if let feedbackMessage {
                    Text(feedbackMessage)
                        .font(DesignTypography.metadata)
                        .foregroundStyle(palette.negative)
                        .fixedSize(horizontal: false, vertical: true)
                }

                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(searchModel.results) { instrument in
                            searchResultRow(instrument)

                            if instrument.id != searchModel.results.last?.id {
                                Rectangle()
                                    .fill(palette.border)
                                    .frame(height: 1)
                            }
                        }
                    }
                }
                .background(palette.surface)
                .clipShape(.rect(cornerRadius: DesignMetrics.cornerRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: DesignMetrics.cornerRadius)
                        .stroke(palette.border, lineWidth: 1)
                }
            }
        }
    }

    private func searchResultRow(_ instrument: Instrument) -> some View {
        let isAdded = store.instruments.contains { $0.id == instrument.id }

        return HStack(spacing: DesignMetrics.space12) {
            VStack(alignment: .leading, spacing: DesignMetrics.space4) {
                Text(instrument.name)
                    .font(DesignTypography.bodyMedium)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                Text("\(instrument.symbol) · \(instrument.namespace.displayName)")
                    .font(DesignTypography.metadata)
                    .monospacedDigit()
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Button(isAdded ? "已添加" : "添加") {
                add(instrument)
            }
            .buttonStyle(.bordered)
            .disabled(isAdded || store.isWatchlistMutating)
            .accessibilityLabel(
                AddInstrumentAccessibility.resultActionLabel(
                    for: instrument,
                    isAdded: isAdded
                )
            )
        }
        .padding(.horizontal, DesignMetrics.space12)
        .frame(minHeight: DesignMetrics.dataRowHeight)
    }

    private var cleanQuery: String {
        searchModel.query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var searchStatusIcon: String {
        if searchModel.hasSearchFailure { return "exclamationmark.triangle" }
        if searchModel.message != nil { return "magnifyingglass" }
        return "text.magnifyingglass"
    }

    private var searchStatusTitle: String {
        if searchModel.hasSearchFailure { return tr("搜索失败") }
        if searchModel.message != nil { return tr("没有结果") }
        return tr("搜索标的")
    }

    private var searchStatusMessage: String {
        feedbackMessage
            ?? searchModel.message
            ?? tr("输入名称或代码，结果会显示在这里。")
    }

    private func add(_ instrument: Instrument) {
        feedbackMessage = nil
        Task {
            if let message = await store.add(instrument) {
                feedbackMessage = message
                return
            }
            onAdded(instrument)
            dismiss()
        }
    }
}
