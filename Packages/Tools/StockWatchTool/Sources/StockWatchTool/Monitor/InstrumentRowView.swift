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

    @Environment(\.designPalette) private var palette

    var body: some View {
        ViewThatFits(in: .horizontal) {
            wideContent
                .frame(minWidth: StockWatchRowLayout.wideMinimumWidth)

            compactContent
        }
        .padding(.horizontal, DesignMetrics.space12)
        .frame(
            maxWidth: .infinity,
            minHeight: DesignMetrics.dataRowHeight + DesignMetrics.space16,
            alignment: .leading
        )
        .contentShape(.rect)
        .accessibilityElement(children: .contain)
    }

    private var wideContent: some View {
        HStack(spacing: DesignMetrics.space12) {
            identity
                .frame(width: 132, alignment: .leading)

            intradayChart
                .frame(minWidth: 0, maxWidth: .infinity)

            price
                .frame(width: 108, alignment: .trailing)
                .accessibilityHidden(true)
        }
    }

    private var compactContent: some View {
        HStack(spacing: DesignMetrics.space12) {
            identity

            price
                .frame(width: 96, alignment: .trailing)
                .accessibilityHidden(true)
        }
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: DesignMetrics.space4) {
            Text(instrument.name)
                .font(DesignTypography.bodyMedium)
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)

            Text("\(instrument.symbol) · \(instrument.namespace.displayName)")
                .font(DesignTypography.metadata)
                .monospacedDigit()
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1)

            if let statusText {
                Label(statusText, systemImage: statusIcon)
                    .font(DesignTypography.metadata)
                    .foregroundStyle(statusColor)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    @ViewBuilder
    private var intradayChart: some View {
        if let chart, chart.points.count > 1 {
            IntradayChartView(chart: chart)
                .frame(maxWidth: .infinity, minHeight: 44, maxHeight: 48)
        } else {
            HStack(spacing: DesignMetrics.space8) {
                if status == .loading {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityHidden(true)
                }
                Text(status == .loading ? "正在准备分时" : "等待分时数据")
                    .font(DesignTypography.metadata)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(palette.surfaceElevated)
            .clipShape(.rect(cornerRadius: DesignMetrics.space4))
            .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var price: some View {
        if let quote {
            VStack(alignment: .trailing, spacing: DesignMetrics.space4) {
                Text(InstrumentRowPresentation.priceText(quote.lastPrice))
                    .font(DesignTypography.sectionTitle)
                    .monospacedDigit()
                    .foregroundStyle(priceColor(for: quote))

                Label(
                    InstrumentRowPresentation.percentText(quote.changePercent),
                    systemImage: directionIcon(for: quote.changePercent)
                )
                .font(DesignTypography.metadata)
                .monospacedDigit()
                .foregroundStyle(priceColor(for: quote))
                .lineLimit(1)
            }
        } else {
            Text(status == .loading ? "拉取中" : "暂无报价")
                .font(DesignTypography.metadata)
                .foregroundStyle(palette.textSecondary)
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
        case .idle, .live:
            return "clock"
        }
    }

    private var statusColor: Color {
        if status == .stale || (status == .idle && statusMessage != nil) {
            return palette.warning
        }
        return palette.textSecondary
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
