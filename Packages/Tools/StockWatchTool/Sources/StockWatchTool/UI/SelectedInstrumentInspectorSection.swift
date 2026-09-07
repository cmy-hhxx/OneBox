import OneBoxDesignSystem
import SwiftUI

enum SelectedInstrumentQuotePresentation {
    static func livePrice(status: MonitorStatus?, lastPrice: Double?) -> Double? {
        guard status == .live,
            let lastPrice,
            lastPrice.isFinite,
            lastPrice > 0
        else {
            return nil
        }
        return lastPrice
    }
}

@MainActor
struct SelectedInstrumentInspectorSection: View {
    let store: MonitorStore
    let selectedInstrumentID: InstrumentID?

    private let watchlistPresentation: WatchlistPresentationSession
    private let quotePresentation: QuotePresentationSession
    private let alertPresentation: AlertPresentationSession

    @Environment(\.designPalette) private var palette
    @State private var removalCandidate: Instrument?

    init(store: MonitorStore, selectedInstrumentID: InstrumentID?) {
        self.store = store
        self.selectedInstrumentID = selectedInstrumentID
        self.watchlistPresentation = store.watchlistPresentation
        self.quotePresentation = store.quotePresentation
        self.alertPresentation = store.alertPresentation
    }

    private var selectedInstrument: Instrument? {
        watchlistPresentation.instruments.first { $0.id == selectedInstrumentID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignMetrics.space12) {
            Text("所选标的")
                .font(DesignTypography.sectionTitle)
                .accessibilityAddTraits(.isHeader)

            if let instrument = selectedInstrument {
                identity(instrument)
                actions(instrument)
                targetPriceControls(instrument)
            } else {
                Label("请在行情列表中选择一个标的", systemImage: "cursorarrow.click")
                    .font(DesignTypography.metadata)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .confirmationDialog(
            "移除观察标的？",
            isPresented: Binding(
                get: { removalCandidate != nil },
                set: { isPresented in
                    if !isPresented { removalCandidate = nil }
                }
            ),
            titleVisibility: .visible,
            presenting: removalCandidate
        ) { instrument in
            Button("移除 \(instrument.name)", role: .destructive) {
                Task { await store.remove(instrument) }
            }
            Button("取消", role: .cancel) {}
        } message: { instrument in
            Text(
                "移除 \(instrument.name) 后，会同时删除它的价格目标和行情缓存。此操作不可撤销。"
            )
        }
    }

    private func identity(_ instrument: Instrument) -> some View {
        let monitored = quotePresentation.snapshot.monitoredInstruments[instrument.id]
        let livePrice = SelectedInstrumentQuotePresentation.livePrice(
            status: monitored?.status,
            lastPrice: monitored?.quote?.lastPrice
        )

        return VStack(alignment: .leading, spacing: DesignMetrics.space4) {
            Text(instrument.name)
                .font(DesignTypography.bodyMedium)
                .lineLimit(1)
            Text("\(instrument.symbol) · \(instrument.namespace.displayName)")
                .font(DesignTypography.metadata)
                .monospacedDigit()
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1)

            if let livePrice {
                Text(
                    String(
                        format: tr("现价 %@%.2f"),
                        instrument.market.currencySymbol,
                        livePrice
                    )
                )
                .font(DesignTypography.metadata)
                .monospacedDigit()
                .foregroundStyle(palette.textSecondary)
            } else {
                Text("等待实时价格")
                    .font(DesignTypography.metadata)
                    .foregroundStyle(palette.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func actions(_ instrument: Instrument) -> some View {
        let index = watchlistPresentation.instruments.firstIndex { $0.id == instrument.id }

        return HStack(spacing: DesignMetrics.space8) {
            Button("上移", systemImage: "arrow.up") {
                move(instrument, direction: -1)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.bordered)
            .disabled(index == nil || index == 0 || watchlistPresentation.isMutating)
            .help("在观察列表中上移")
            .accessibilityLabel("上移 \(instrument.name)")

            Button("下移", systemImage: "arrow.down") {
                move(instrument, direction: 1)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.bordered)
            .disabled(
                index == nil
                    || index == watchlistPresentation.instruments.count - 1
                    || watchlistPresentation.isMutating
            )
            .help("在观察列表中下移")
            .accessibilityLabel("下移 \(instrument.name)")

            Spacer(minLength: 0)

            Button("移除", systemImage: "trash", role: .destructive) {
                removalCandidate = instrument
            }
            .buttonStyle(.bordered)
            .disabled(watchlistPresentation.isMutating)
        }
        .controlSize(.small)
    }

    private func targetPriceControls(_ instrument: Instrument) -> some View {
        let monitored = quotePresentation.snapshot.monitoredInstruments[instrument.id]
        let targets =
            alertPresentation.priceTargets[instrument.id]
            ?? PriceAlertTargets(risingPrice: nil, fallingPrice: nil)
        let hasLivePrice =
            SelectedInstrumentQuotePresentation.livePrice(
                status: monitored?.status,
                lastPrice: monitored?.quote?.lastPrice
            ) != nil

        return VStack(alignment: .leading, spacing: DesignMetrics.space8) {
            Toggle(
                "目标价格",
                isOn: Binding(
                    get: { targets.isEnabled },
                    set: { isEnabled in
                        guard !isEnabled || hasLivePrice else { return }
                        store.setPriceTargetsEnabled(for: instrument, enabled: isEnabled)
                    }
                )
            )
            .toggleStyle(.switch)
            .disabled(!hasLivePrice && !targets.isEnabled)
            .accessibilityHint(
                hasLivePrice ? "开启后设置上涨和下跌目标" : "等待实时价格后才能开启"
            )

            if targets.isEnabled {
                targetPriceField(
                    title: "上涨价 ≥",
                    instrument: instrument,
                    isRising: true
                )
                targetPriceField(
                    title: "下跌价 ≤",
                    instrument: instrument,
                    isRising: false
                )
            }

            if alertPresentation.configuration.basis != .targetPrice {
                Text("切换提醒依据为“目标价格”后生效。")
                    .font(DesignTypography.metadata)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func targetPriceField(
        title: String,
        instrument: Instrument,
        isRising: Bool
    ) -> some View {
        HStack(spacing: DesignMetrics.space8) {
            Text(title)
                .font(DesignTypography.metadata)
                .foregroundStyle(palette.textSecondary)
            Spacer(minLength: 0)
            Text(instrument.market.currencySymbol)
                .font(DesignTypography.metadata)
                .foregroundStyle(palette.textSecondary)
            TextField(
                title,
                value: priceBinding(for: instrument, isRising: isRising),
                format: .number.precision(.fractionLength(2))
            )
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.trailing)
            .monospacedDigit()
            .frame(width: 84)
            .accessibilityLabel("\(instrument.name) \(title)")
        }
    }

    private func priceBinding(
        for instrument: Instrument,
        isRising: Bool
    ) -> Binding<Double> {
        Binding(
            get: {
                let targets = alertPresentation.priceTargets[instrument.id]
                return isRising ? targets?.risingPrice ?? 0 : targets?.fallingPrice ?? 0
            },
            set: { value in
                let targets =
                    alertPresentation.priceTargets[instrument.id]
                    ?? PriceAlertTargets(risingPrice: nil, fallingPrice: nil)
                store.updatePriceTargets(
                    for: instrument,
                    risingPrice: isRising ? value : targets.risingPrice,
                    fallingPrice: isRising ? targets.fallingPrice : value
                )
            }
        )
    }

    private func move(_ instrument: Instrument, direction: Int) {
        guard
            let index = watchlistPresentation.instruments.firstIndex(where: {
                $0.id == instrument.id
            })
        else {
            return
        }
        let destination = direction < 0 ? index - 1 : index + 2
        Task {
            await store.moveInstruments(from: IndexSet(integer: index), to: destination)
        }
    }
}
