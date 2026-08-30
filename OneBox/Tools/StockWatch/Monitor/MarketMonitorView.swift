import OneBoxDesignSystem
import SwiftUI

@MainActor
struct MarketMonitorView: View {
    @ObservedObject var store: MonitorStore
    @Binding var selectedInstrumentID: InstrumentID?
    let openAddInstrument: () -> Void

    @Environment(\.designPalette) private var palette

    var body: some View {
        VStack(spacing: 0) {
            statusBanners

            if store.instruments.isEmpty {
                emptyState
            } else {
                instrumentList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(palette.surface)
        .clipShape(.rect(cornerRadius: DesignMetrics.cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: DesignMetrics.cornerRadius)
                .stroke(palette.border, lineWidth: 1)
        }
    }

    @ViewBuilder
    private var statusBanners: some View {
        if let storageError = store.storageError {
            MarketErrorBanner(
                title: "本地存储需要处理",
                message: storageError,
                systemImage: "externaldrive.badge.exclamationmark",
                actionTitle: "关闭提示",
                action: store.dismissStorageError
            )
        }

        if let sourceError = store.sourceError {
            MarketErrorBanner(
                title: "行情刷新失败",
                message: sourceError,
                systemImage: "wifi.exclamationmark",
                actionTitle: "重试"
            ) {
                Task { await store.refreshAll() }
            }
        }
    }

    private var instrumentList: some View {
        List(selection: $selectedInstrumentID) {
            ForEach(store.instruments) { instrument in
                let monitored = store.monitoredInstrument(for: instrument.id)
                InstrumentRowView(
                    instrument: instrument,
                    quote: monitored?.quote,
                    status: monitored?.status ?? .idle,
                    statusMessage: monitored?.statusMessage
                )
                .tag(instrument.id)
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.visible, edges: .bottom)
                .listRowBackground(
                    selectedInstrumentID == instrument.id
                        ? palette.selection
                        : palette.surface
                )
            }
            .onMove { offsets, destination in
                Task {
                    await store.moveInstruments(from: offsets, to: destination)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(
            \.defaultMinListRowHeight,
            DesignMetrics.dataRowHeight + DesignMetrics.space16
        )
        .disabled(store.isWatchlistMutating)
        .accessibilityLabel("观察列表，共 \(store.instruments.count) 个标的")
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("观察列表为空", systemImage: "list.star")
        } description: {
            Text("添加名称或代码，开始查看实时行情。")
                .font(DesignTypography.body)
        } actions: {
            Button("添加标的", systemImage: "plus", action: openAddInstrument)
                .buttonStyle(.borderedProminent)
                .tint(palette.accent)
        }
        .font(DesignTypography.body)
        .foregroundStyle(palette.textPrimary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

enum MonitorStatusIndicator: Equatable {
    case source(String)
    case storage(String)

    init?(sourceError: String?, storageError: String?) {
        if let storageError {
            self = .storage(storageError)
        } else if let sourceError {
            self = .source(sourceError)
        } else {
            return nil
        }
    }

    var icon: String {
        switch self {
        case .source:
            "wifi.exclamationmark"
        case .storage:
            "externaldrive.badge.exclamationmark"
        }
    }

    var message: String {
        switch self {
        case .source(let message), .storage(let message):
            message
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .source:
            tr("行情数据需要注意")
        case .storage:
            tr("本地存储需要注意")
        }
    }
}

@MainActor
private struct MarketErrorBanner: View {
    let title: String
    let message: String
    let systemImage: String
    let actionTitle: String
    let action: () -> Void

    @Environment(\.designPalette) private var palette

    var body: some View {
        HStack(spacing: DesignMetrics.space8) {
            Label(title, systemImage: systemImage)
                .font(DesignTypography.bodyMedium)
                .foregroundStyle(palette.warning)
                .lineLimit(1)

            Text(message)
                .font(DesignTypography.metadata)
                .foregroundStyle(palette.textSecondary)
                .lineLimit(2)

            Spacer(minLength: 0)

            Button(actionTitle, action: action)
                .buttonStyle(.borderless)
                .font(DesignTypography.bodyMedium)
                .foregroundStyle(palette.textPrimary)
        }
        .padding(.horizontal, DesignMetrics.space12)
        .frame(minHeight: DesignMetrics.space32)
        .background(palette.surfaceElevated)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(palette.border)
                .frame(height: 1)
        }
        .accessibilityElement(children: .combine)
    }
}
