import OneBoxDesignSystem
import SwiftUI

enum InstrumentRowPresentation {
    static func statusText(
        status: MonitorStatus,
        hasQuote: Bool,
        statusMessage: String?
    ) -> String? {
        switch status {
        case .idle:
            guard !hasQuote else { return nil }
            return statusMessage ?? tr("等待首次刷新")
        case .loading:
            return tr("正在刷新")
        case .live:
            return nil
        case .previousSession:
            return statusMessage ?? tr("最近交易日行情")
        case .stale:
            return statusMessage ?? tr("行情已过期")
        }
    }

    static func priceText(_ value: Double) -> String {
        String(format: value < 10 ? "%.3f" : "%.2f", value)
    }

    static func percentText(_ value: Double) -> String {
        String(format: "%@%.2f%%", value > 0 ? "+" : "", value)
    }

    static func accessibilitySummary(
        instrument: Instrument,
        quote: QuoteSnapshot?,
        status: MonitorStatus,
        statusMessage: String?
    ) -> String {
        let quoteSummary: String
        if let quote {
            let direction: String
            if quote.changePercent > 0 {
                direction = tr("上涨")
            } else if quote.changePercent < 0 {
                direction = tr("下跌")
            } else {
                direction = tr("持平")
            }
            quoteSummary =
                "\(priceText(quote.lastPrice))，\(direction) \(percentText(quote.changePercent))"
        } else {
            quoteSummary = status == .loading ? tr("正在拉取行情") : tr("暂无行情")
        }
        let stateSummary =
            statusText(
                status: status,
                hasQuote: quote != nil,
                statusMessage: statusMessage
            ).map { "，\($0)" } ?? ""
        return
            "\(instrument.name)，\(instrument.symbol)，\(instrument.namespace.displayName)，\(quoteSummary)\(stateSummary)"
    }
}

enum StockWatchRowField: Hashable {
    case identity
    case code
    case status
    case price
    case changeDirection
    case intradayChart
}

/// `ViewThatFits` selects between these stable row shapes without measuring
/// the workspace or introducing a second scrolling axis.
enum StockWatchRowLayout: Equatable {
    case wide
    case compact

    static let wideMinimumWidth: CGFloat = 420
    static let identityColumnWidth: CGFloat = 164
    static let priceColumnWidth: CGFloat = 104

    var visibleFields: Set<StockWatchRowField> {
        switch self {
        case .wide:
            [.identity, .code, .status, .price, .changeDirection, .intradayChart]
        case .compact:
            [.identity, .code, .status, .price, .changeDirection]
        }
    }
}

struct InstrumentRowView: View {
    let instrument: Instrument
    let quote: QuoteSnapshot?
    let chart: PreparedIntradayChart?
    let status: MonitorStatus
    let statusMessage: String?
    var isSelected = false

    @Environment(\.designPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: DesignMetrics.space8) {
            ViewThatFits(in: .horizontal) {
                wideContent
                    .frame(minWidth: StockWatchRowLayout.wideMinimumWidth)

                compactContent
            }

            if let statusText {
                Label(statusText, systemImage: statusIcon)
                    .font(DesignTypography.metadata)
                    .foregroundStyle(statusColor)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .help(statusText)
                    .accessibilityHidden(true)
            }
        }
        // The native macOS List cell adds 8pt; the total matches BoardUI's 12pt cell inset.
        .padding(.horizontal, DesignMetrics.space4)
        .padding(.vertical, 10)
        .frame(
            maxWidth: .infinity,
            minHeight: 64,
            alignment: .leading
        )
        .contentShape(.rect)
        .accessibilityElement(children: .contain)
    }

    private var wideContent: some View {
        HStack(spacing: DesignMetrics.space12) {
            identity
                .frame(width: StockWatchRowLayout.identityColumnWidth, alignment: .leading)

            intradayChart
                .frame(minWidth: 0, maxWidth: .infinity)

            price
                .frame(width: StockWatchRowLayout.priceColumnWidth, alignment: .trailing)
                .accessibilityHidden(true)
        }
    }

    private var compactContent: some View {
        HStack(spacing: DesignMetrics.space12) {
            identity

            price
                .frame(width: StockWatchRowLayout.priceColumnWidth, alignment: .trailing)
                .accessibilityHidden(true)
        }
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: DesignMetrics.space4) {
            Text(instrument.name)
                .font(DesignTypography.bodyMedium)
                .foregroundStyle(palette.textPrimary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .help(instrument.name)

            Text("\(instrument.symbol) · \(instrument.namespace.displayName)")
                .font(DesignTypography.metadata)
                .monospacedDigit()
                .foregroundStyle(metadataColor)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    @ViewBuilder
    private var intradayChart: some View {
        if let chart, !chart.points.isEmpty {
            IntradayChartView(chart: chart)
                .frame(maxWidth: .infinity, minHeight: 48, maxHeight: 52)
        } else {
            HStack(spacing: DesignMetrics.space8) {
                if status == .loading {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityHidden(true)
                }
                Text(status == .loading ? "正在准备分时" : "等待分时数据")
                    .font(DesignTypography.metadata)
                    .foregroundStyle(metadataColor)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var price: some View {
        if let quote {
            VStack(alignment: .trailing, spacing: DesignMetrics.space4) {
                Text(InstrumentRowPresentation.priceText(quote.lastPrice))
                    .font(DesignTypography.bodyMedium)
                    .monospacedDigit()
                    .foregroundStyle(priceColor(for: quote))

                Label(
                    InstrumentRowPresentation.percentText(quote.changePercent),
                    systemImage: directionIcon(for: quote.changePercent)
                )
                .font(DesignTypography.bodyMedium)
                .monospacedDigit()
                .foregroundStyle(priceColor(for: quote))
                .lineLimit(1)
            }
        } else {
            Text(status == .loading ? "拉取中" : "暂无报价")
                .font(DesignTypography.metadata)
                .foregroundStyle(metadataColor)
        }
    }

    private var statusText: String? {
        InstrumentRowPresentation.statusText(
            status: status,
            hasQuote: quote != nil,
            statusMessage: statusMessage
        )
    }

    private var statusIcon: String {
        if status == .idle, statusMessage != nil {
            return "exclamationmark.triangle"
        }
        switch status {
        case .stale:
            return "clock.badge.exclamationmark"
        case .loading:
            return "arrow.clockwise"
        case .idle, .live, .previousSession:
            return "clock"
        }
    }

    private var statusColor: Color {
        if status == .stale || (status == .idle && statusMessage != nil) {
            return palette.warning
        }
        return metadataColor
    }

    private var metadataColor: Color {
        isSelected ? palette.textPrimary : palette.textSecondary
    }

    private func changeRole(for quote: QuoteSnapshot) -> MarketColorRole {
        instrument.market.colorRole(forChange: quote.changePercent)
    }

    private func priceColor(for quote: QuoteSnapshot) -> Color {
        guard quote.changePercent != 0 else { return palette.textPrimary }
        return changeRole(for: quote).color(in: palette)
    }

    private func directionIcon(for value: Double) -> String {
        if value > 0 { return "arrow.up.right" }
        if value < 0 { return "arrow.down.right" }
        return "minus"
    }

    private var accessibilitySummary: String {
        InstrumentRowPresentation.accessibilitySummary(
            instrument: instrument,
            quote: quote,
            status: status,
            statusMessage: statusMessage
        )
    }
}
