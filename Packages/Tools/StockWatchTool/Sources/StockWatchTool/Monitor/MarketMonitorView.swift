import OneBoxDesignSystem
import OneBoxRuntime
import SwiftUI

@MainActor
struct MarketMonitorView: View {
    let store: MonitorStore
    @Binding var selectedInstrumentID: InstrumentID?
    let openAddInstrument: () -> Void

    private let watchlistPresentation: WatchlistPresentationSession
    private let quotePresentation: QuotePresentationSession
    private let diagnosticsPresentation: DiagnosticsPresentationSession

    @Environment(\.designPalette) private var palette

    init(
        store: MonitorStore,
        selectedInstrumentID: Binding<InstrumentID?>,
        openAddInstrument: @escaping () -> Void
    ) {
        self.store = store
        _selectedInstrumentID = selectedInstrumentID
        self.openAddInstrument = openAddInstrument
        self.watchlistPresentation = store.watchlistPresentation
        self.quotePresentation = store.quotePresentation
        self.diagnosticsPresentation = store.diagnosticsPresentation
    }

    var body: some View {
        VStack(spacing: DesignMetrics.space12) {
            statusBanners
            GeometryReader { geometry in
                let selected = selectedQuote
                let showsDetail = selected != nil && geometry.size.height >= 360
                VStack(spacing: DesignMetrics.space12) {
                    tableContent
                        .frame(
                            height: showsDetail ? watchlistHeight(in: geometry.size.height) : nil)
                    if showsDetail, let selected {
                        StockIntradayDetailView(
                            instrument: selected.instrument, quote: selected.quote,
                            chart: selected.chart, status: selected.status
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var selectedQuote:
        (
            instrument: Instrument, quote: QuoteSnapshot, chart: PreparedIntradayChart,
            status: MonitorStatus
        )?
    {
        guard let selectedInstrumentID,
            let instrument = watchlistPresentation.instruments.first(where: {
                $0.id == selectedInstrumentID
            }),
            let monitored = quotePresentation.snapshot.monitoredInstruments[selectedInstrumentID],
            let quote = monitored.quote, let chart = monitored.chart, !chart.points.isEmpty
        else { return nil }
        return (instrument, quote, chart, monitored.status)
    }

    private func watchlistHeight(in availableHeight: CGFloat) -> CGFloat {
        // Keep one complete row visible; additional symbols scroll while the selected
        // instrument gets the rest of the workspace for a legible price chart.
        let desired = CGFloat(watchlistPresentation.instruments.count) * 100 + 80
        return min(desired, max(180, min(220, availableHeight * 0.4)))
    }

    private var tableContent: some View {
        VStack(spacing: 0) {
            if watchlistPresentation.instruments.isEmpty {
                emptyState
            } else {
                listHeading
                instrumentList
                listFooter
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(palette.surface)
        .clipShape(.rect(cornerRadius: DesignMetrics.space16))
        .overlay {
            RoundedRectangle(cornerRadius: DesignMetrics.space16)
                .strokeBorder(palette.border, lineWidth: 1)
        }
    }

    @ViewBuilder
    private var statusBanners: some View {
        if let storageError = diagnosticsPresentation.storageError {
            MarketErrorBanner(
                title: "本地存储需要处理",
                message: storageError,
                systemImage: "externaldrive.badge.exclamationmark",
                isStorageFailure: true,
                actionTitle: "关闭提示",
                action: store.dismissStorageError
            )
        }

        if let sourceError = quotePresentation.snapshot.sourceError {
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

    private var listHeading: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: DesignMetrics.space12) {
                Text("标的 / 市场")
                    .frame(width: StockWatchRowLayout.identityColumnWidth, alignment: .leading)
                Text("分时走势")
                    .frame(maxWidth: .infinity)
                Text("价格 / 涨跌")
                    .frame(width: StockWatchRowLayout.priceColumnWidth, alignment: .trailing)
            }
            .frame(minWidth: StockWatchRowLayout.wideMinimumWidth)

            HStack(spacing: DesignMetrics.space12) {
                Text("标的 / 市场")
                Spacer(minLength: 0)
                Text("价格 / 涨跌")
            }
        }
        .font(DesignTypography.bodyMedium)
        .foregroundStyle(palette.textPrimary)
        .padding(.horizontal, DesignMetrics.space12)
        .frame(height: 40)
        .background(palette.surfaceElevated)
        .overlay(alignment: .bottom) {
            Rectangle().fill(palette.border).frame(height: 1)
        }
        .accessibilityHidden(true)
    }

    private var listFooter: some View {
        HStack(spacing: DesignMetrics.space12) {
            Text("\(watchlistPresentation.instruments.count) 个标的")
                .monospacedDigit()
            Spacer(minLength: 0)
            Text("拖动行调整顺序")
        }
        .font(DesignTypography.metadata)
        .foregroundStyle(palette.textSecondary)
        .padding(.horizontal, DesignMetrics.space12)
        .frame(height: 32)
        .overlay(alignment: .top) {
            Rectangle().fill(palette.border).frame(height: 1)
        }
    }

    private var instrumentList: some View {
        List(selection: $selectedInstrumentID) {
            ForEach(watchlistPresentation.instruments) { instrument in
                let monitored = quotePresentation.snapshot.monitoredInstruments[instrument.id]
                InstrumentRowView(
                    instrument: instrument,
                    quote: monitored?.quote,
                    chart: monitored?.chart,
                    status: monitored?.status ?? .idle,
                    statusMessage: monitored?.statusMessage,
                    isSelected: selectedInstrumentID == instrument.id
                )
                .tag(instrument.id)
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(
                    Rectangle()
                        .fill(
                            selectedInstrumentID == instrument.id
                                ? palette.surfaceElevated : palette.surface
                        )
                        .overlay(alignment: .bottom) {
                            if instrument.id != watchlistPresentation.instruments.last?.id {
                                Rectangle().fill(palette.border).frame(height: 1)
                            }
                        }
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
            64
        )
        .disabled(watchlistPresentation.isMutating)
        .accessibilityLabel("观察列表，共 \(watchlistPresentation.instruments.count) 个标的")
    }

    private var emptyState: some View {
        VStack(spacing: DesignMetrics.space12) {
            Text("观察列表为空")
                .font(DesignTypography.bodyMedium)
                .foregroundStyle(palette.textPrimary)
            Text("搜索 A股、港股或美股，将关心的标的放在一起。")
                .font(DesignTypography.body)
                .foregroundStyle(palette.textSecondary)
                .multilineTextAlignment(.center)
            Button("添加标的", systemImage: "plus", action: openAddInstrument)
                .buttonStyle(ToolActionButtonStyle(kind: .primary))
        }
        .padding(DesignMetrics.space24)
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
    var isStorageFailure = false
    let actionTitle: String
    let action: () -> Void

    @Environment(\.designPalette) private var palette
    @Environment(\.openToolDiagnostics) private var openDiagnostics

    var body: some View {
        HStack(alignment: .top, spacing: DesignMetrics.space12) {
            Image(systemName: systemImage)
                .font(DesignTypography.metric)
                .foregroundStyle(isStorageFailure ? palette.negative : palette.warning)
                .frame(width: 40, height: 40)
                .background(
                    isStorageFailure ? palette.negativeSurface : palette.warningSurface,
                    in: .circle
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: DesignMetrics.space4) {
                Text(title)
                    .font(DesignTypography.bodyMedium)
                    .foregroundStyle(palette.textPrimary)
                Text(message)
                    .font(DesignTypography.body)
                    .foregroundStyle(palette.textSecondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: DesignMetrics.space8) {
                    Button(actionTitle, action: action)
                        .buttonStyle(ToolActionButtonStyle(kind: .secondary, compact: true))
                    Button("查看日志") { openDiagnostics() }
                        .buttonStyle(ToolActionButtonStyle(kind: .quiet, compact: true))
                }
                .padding(.top, DesignMetrics.space8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(DesignMetrics.space16)
        .background(palette.surface, in: .rect(cornerRadius: DesignMetrics.space16))
        .overlay {
            RoundedRectangle(cornerRadius: DesignMetrics.space16)
                .strokeBorder(palette.border, lineWidth: 1)
        }
        .shadow(color: palette.dropdownContactShadow, radius: 1, x: 0, y: 1)
        .shadow(color: palette.dropdownAmbientShadow, radius: 4, x: 0, y: 4)
        .accessibilityElement(children: .contain)
    }
}
