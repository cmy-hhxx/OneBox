import OneBoxDesignSystem
import SwiftUI

enum WatchlistJSONPresentation {
    static let replacementWarning =
        "导入会整体替换当前列表，并删除 JSON 未保留标的的目标价格和行情缓存。此操作不可撤销。"

    static func confirmationMessage(currentCount: Int) -> String {
        "当前 \(currentCount) 个标的将被 JSON 中的列表替换；JSON 未保留标的的目标价格和行情缓存将被删除。此操作不可撤销。"
    }

    static func canImport(_ json: String) -> Bool {
        !json.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

@MainActor
struct WatchlistJSONSheet: View {
    let store: MonitorStore
    let copyText: (String) -> Bool
    let onImported: () -> Void

    private let watchlistPresentation: WatchlistPresentationSession

    @Environment(\.designPalette) private var palette
    @Environment(\.dismiss) private var dismiss
    @State private var jsonText = ""
    @State private var resultMessage: String?
    @State private var isImporting = false
    @State private var isConfirmingReplacement = false

    init(
        store: MonitorStore,
        copyText: @escaping (String) -> Bool,
        onImported: @escaping () -> Void
    ) {
        self.store = store
        self.copyText = copyText
        self.onImported = onImported
        self.watchlistPresentation = store.watchlistPresentation
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignMetrics.space16) {
            header
            irreversibleWarning
            actions
            editor
            footer
        }
        .padding(DesignMetrics.space24)
        .frame(width: 520, height: 480, alignment: .topLeading)
        .background(palette.background)
        .onAppear {
            guard jsonText.isEmpty else { return }
            jsonText = store.watchlistJSONExample()
        }
        .confirmationDialog(
            "用 JSON 替换当前观察列表？",
            isPresented: $isConfirmingReplacement,
            titleVisibility: .visible
        ) {
            Button("替换观察列表", role: .destructive, action: applyImport)
            Button("取消", role: .cancel) {}
        } message: {
            Text(
                WatchlistJSONPresentation.confirmationMessage(
                    currentCount: watchlistPresentation.instruments.count
                )
            )
        }
    }

    private var header: some View {
        HStack {
            Text("批量替换观察列表")
                .font(DesignTypography.metric)
                .foregroundStyle(palette.textPrimary)

            Spacer(minLength: 0)

            Button("关闭", systemImage: "xmark") {
                dismiss()
            }
            .labelStyle(.iconOnly)
            .buttonStyle(ToolCloseButtonStyle())
            .keyboardShortcut(.cancelAction)
            .accessibilityLabel("关闭批量替换")
        }
    }

    private var irreversibleWarning: some View {
        Label(
            WatchlistJSONPresentation.replacementWarning,
            systemImage: "exclamationmark.triangle"
        )
        .font(DesignTypography.metadata)
        .foregroundStyle(palette.negative)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var actions: some View {
        HStack(spacing: DesignMetrics.space8) {
            Button("填入当前列表") {
                jsonText = store.watchlistJSONExample()
                resultMessage = "已填入当前列表"
            }
            .buttonStyle(ToolActionButtonStyle(kind: .secondary, compact: true))

            Button("复制当前列表", systemImage: "doc.on.doc") {
                let value = store.watchlistJSONExample()
                jsonText = value
                resultMessage = copyText(value) ? "已复制当前列表" : "复制失败，请重试"
            }
            .buttonStyle(ToolActionButtonStyle(kind: .secondary, compact: true))

            Spacer(minLength: 0)
        }
        .font(DesignTypography.bodyMedium)
    }

    private var editor: some View {
        TextEditor(text: $jsonText)
            .font(DesignTypography.diagnostic)
            .foregroundStyle(palette.textPrimary)
            .scrollContentBackground(.hidden)
            .padding(DesignMetrics.space8)
            .background(palette.surface)
            .clipShape(.rect(cornerRadius: DesignMetrics.cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: DesignMetrics.cornerRadius)
                    .stroke(palette.border, lineWidth: 1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityLabel("观察列表 JSON")
    }

    private var footer: some View {
        HStack(spacing: DesignMetrics.space12) {
            if let resultMessage {
                Text(resultMessage)
                    .font(DesignTypography.metadata)
                    .foregroundStyle(
                        resultMessage.hasPrefix("已")
                            ? palette.textSecondary
                            : palette.negative
                    )
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            Button("替换列表", systemImage: "arrow.triangle.2.circlepath") {
                isConfirmingReplacement = true
            }
            .buttonStyle(ToolActionButtonStyle(kind: .primary))
            .disabled(!canImport || isImporting || watchlistPresentation.isMutating)
            .keyboardShortcut(.defaultAction)
        }
    }

    private var canImport: Bool {
        WatchlistJSONPresentation.canImport(jsonText)
    }

    private func applyImport() {
        guard !isImporting else { return }
        isImporting = true
        resultMessage = nil
        Task {
            let result = await store.importWatchlist(fromJSON: jsonText)
            isImporting = false
            switch result {
            case .success:
                onImported()
                dismiss()
            case .failure(let message):
                resultMessage = message
            }
        }
    }
}
