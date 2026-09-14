import OneBoxDesignSystem
import SwiftUI

struct StockIntradayChartLayout {
    let plotRect: CGRect
    let low: Double
    let high: Double

    init(size: CGSize, low: Double, high: Double) {
        plotRect = CGRect(
            x: 4,
            y: 8,
            width: max(size.width - 76, 1),
            height: max(size.height - 32, 1)
        )
        self.low = low
        self.high = high
    }

    func point(progress: Double, price: Double) -> CGPoint {
        CGPoint(
            x: plotRect.minX + plotRect.width * min(max(progress, 0), 1),
            y: plotRect.maxY - plotRect.height * (price - low) / (high - low)
        )
    }

    func progress(at x: CGFloat) -> Double {
        min(max((x - plotRect.minX) / plotRect.width, 0), 1)
    }

    static func nearestPointIndex(
        to progress: Double,
        in points: [IntradayChartPoint]
    ) -> Int? {
        guard !points.isEmpty else { return nil }
        var lower = 0
        var upper = points.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if points[middle].progress <= progress {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        guard lower > 0 else { return 0 }
        guard lower < points.count else { return points.count - 1 }
        let previous = lower - 1
        return progress - points[previous].progress <= points[lower].progress - progress
            ? previous : lower
    }
}

struct StockIntradaySessionTick: Equatable {
    let progress: Double
    let label: String

    static func ticks(for market: Market, compact: Bool) -> [Self] {
        let opening = Self(progress: 0, label: "09:30")
        switch market {
        case .aShare:
            let boundary = Self(progress: 0.5, label: "11:30 / 13:00")
            let closing = Self(progress: 1, label: "15:00")
            return compact
                ? [opening, boundary, closing]
                : [
                    opening, Self(progress: 0.25, label: "10:30"), boundary,
                    Self(progress: 0.75, label: "14:00"), closing,
                ]
        case .hongKong:
            let boundary = Self(progress: 150.0 / 330, label: "12:00 / 13:00")
            let closing = Self(progress: 1, label: "16:00")
            return compact
                ? [opening, boundary, closing]
                : [
                    opening, Self(progress: 60.0 / 330, label: "10:30"), boundary,
                    Self(progress: 270.0 / 330, label: "15:00"), closing,
                ]
        case .unitedStates:
            let closing = Self(progress: 1, label: "16:00")
            return compact
                ? [opening, Self(progress: 0.5, label: "12:45"), closing]
                : [
                    opening, Self(progress: 90.0 / 390, label: "11:00"),
                    Self(progress: 210.0 / 390, label: "13:00"),
                    Self(progress: 300.0 / 390, label: "14:30"), closing,
                ]
        }
    }
}

struct StockIntradayDetailView: View {
    let instrument: Instrument
    let quote: QuoteSnapshot
    let chart: PreparedIntradayChart
    let status: MonitorStatus

    @State private var inspectedIndex: Int?
    @FocusState private var isFocused: Bool

    private let palette = DesignPalette.dark

    var body: some View {
        GeometryReader { geometry in
            let compact = geometry.size.width < 440 || geometry.size.height < 220
            VStack(spacing: 8) {
                header(compact: compact)
                plot(compact: compact)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                footer(compact: compact)
            }
            .padding(16)
        }
        .background(palette.background, in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(isFocused ? palette.accent : palette.border, lineWidth: 1)
        }
        .onChange(of: instrument.id) { _, _ in inspectedIndex = nil }
        .onChange(of: chart) { _, _ in inspectedIndex = nil }
    }

    private var inspectedPoint: IntradayChartPoint? {
        guard let inspectedIndex, chart.points.indices.contains(inspectedIndex) else { return nil }
        return chart.points[inspectedIndex]
    }

    private var displayedPrice: Double {
        inspectedPoint?.close ?? quote.lastPrice
    }

    private var displayedTime: Date {
        inspectedPoint?.time ?? quote.marketTime
    }

    private var displayedChange: Double {
        (displayedPrice - quote.previousClose) / quote.previousClose * 100
    }

    private func header(compact: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(instrument.name)
                    .font(DesignTypography.bodyMedium)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                Text(
                    compact
                        ? "\(instrument.symbol) · \(sessionDate)"
                        : "\(instrument.symbol) · \(instrument.market.displayName) · \(sessionDate)"
                )
                .font(DesignTypography.metadata)
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 4) {
                Text("\(instrument.market.currencySymbol)\(priceText(displayedPrice))")
                    .font(compact ? DesignTypography.sectionTitle : DesignTypography.metric)
                    .foregroundStyle(palette.textPrimary)
                    .monospacedDigit()
                HStack(spacing: 8) {
                    Text(timeText(displayedTime))
                        .foregroundStyle(palette.textSecondary)
                    Text(InstrumentRowPresentation.percentText(displayedChange))
                        .foregroundStyle(
                            instrument.market.colorRole(forChange: displayedChange).color(
                                in: palette)
                        )
                }
                .font(DesignTypography.metadata)
                .monospacedDigit()
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .accessibilityElement(children: .combine)
    }

    private func plot(compact: Bool) -> some View {
        GeometryReader { geometry in
            let layout = StockIntradayChartLayout(
                size: geometry.size,
                low: chart.low,
                high: chart.high
            )
            Canvas { context, size in
                drawGrid(context: context, size: size, layout: layout, compact: compact)
                drawCurve(context: context, layout: layout)
                drawReviewMarkers(context: context, layout: layout)
                if let inspectedPoint {
                    drawInspection(context: context, point: inspectedPoint, layout: layout)
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    let index = StockIntradayChartLayout.nearestPointIndex(
                        to: layout.progress(at: location.x),
                        in: chart.points
                    )
                    if inspectedIndex != index { inspectedIndex = index }
                case .ended:
                    if !isFocused { inspectedIndex = nil }
                }
            }
            .onTapGesture { location in
                isFocused = true
                inspectedIndex = StockIntradayChartLayout.nearestPointIndex(
                    to: layout.progress(at: location.x), in: chart.points)
            }
            .focusable()
            .focused($isFocused)
            .focusEffectDisabled()
            .onKeyPress(.leftArrow) { moveInspection(by: -1) }
            .onKeyPress(.rightArrow) { moveInspection(by: 1) }
            .onKeyPress(.escape) {
                guard inspectedIndex != nil else { return .ignored }
                inspectedIndex = nil
                return .handled
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(tr("分时走势"))
            .accessibilityValue(accessibilityReadout)
            .accessibilityHint(tr("使用左右方向键逐分钟查看价格"))
            .accessibilityAdjustableAction { direction in
                _ = moveInspection(by: direction == .increment ? 1 : -1)
            }
        }
    }

    private func footer(compact: Bool) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 5) {
                Circle().fill(palette.accent).frame(width: 5, height: 5)
                Text(tr("分时"))
            }
            Text(statusText)
            Spacer(minLength: 4)
            if chart.reviewMarkers != nil {
                Text(tr("B / S 收盘复盘"))
                    .help(reviewExplanation)
                    .accessibilityLabel(reviewExplanation)
            } else if !compact {
                Text(tr("悬停查看 · ← → 逐分钟"))
            }
        }
        .font(DesignTypography.metadata)
        .foregroundStyle(palette.textSecondary)
        .lineLimit(1)
    }

    private func drawGrid(
        context: GraphicsContext,
        size: CGSize,
        layout: StockIntradayChartLayout,
        compact: Bool
    ) {
        let ticks = StockIntradaySessionTick.ticks(for: instrument.market, compact: compact)
        for tick in ticks {
            let x = layout.point(progress: tick.progress, price: chart.low).x
            var path = Path()
            path.move(to: CGPoint(x: x, y: layout.plotRect.minY))
            path.addLine(to: CGPoint(x: x, y: layout.plotRect.maxY))
            context.stroke(path, with: .color(palette.border.opacity(0.7)), lineWidth: 0.5)
            context.draw(
                Text(tick.label).font(DesignTypography.metadata).foregroundStyle(
                    palette.textSecondary),
                at: CGPoint(x: x, y: size.height - 4),
                anchor: tick.progress == 0
                    ? .bottomLeading : tick.progress == 1 ? .bottomTrailing : .bottom
            )
        }

        let waterY = layout.point(progress: 0, price: chart.previousClose).y
        for fraction in [0.0, 0.5, 1.0] {
            let price = chart.high - (chart.high - chart.low) * fraction
            let y = layout.point(progress: 0, price: price).y
            var path = Path()
            path.move(to: CGPoint(x: layout.plotRect.minX, y: y))
            path.addLine(to: CGPoint(x: layout.plotRect.maxX, y: y))
            context.stroke(path, with: .color(palette.border), lineWidth: 0.5)
            if abs(y - waterY) > 24 {
                context.draw(
                    Text(axisPriceText(price))
                        .font(DesignTypography.metadata).monospacedDigit()
                        .foregroundStyle(palette.textSecondary),
                    at: CGPoint(x: size.width, y: y),
                    anchor: .trailing
                )
            }
        }
        var waterline = Path()
        waterline.move(to: CGPoint(x: layout.plotRect.minX, y: waterY))
        waterline.addLine(to: CGPoint(x: layout.plotRect.maxX, y: waterY))
        context.stroke(
            waterline,
            with: .color(palette.textSecondary.opacity(0.55)),
            style: StrokeStyle(lineWidth: 0.75, dash: [4, 4])
        )
        let waterLabelY = min(max(waterY, 14), max(14, size.height - 36))
        context.draw(
            Text(tr("昨收")).font(DesignTypography.metadata).foregroundStyle(palette.textSecondary),
            at: CGPoint(x: size.width, y: waterLabelY - 7),
            anchor: .trailing
        )
        context.draw(
            Text(priceText(chart.previousClose))
                .font(DesignTypography.metadata).monospacedDigit()
                .foregroundStyle(palette.textPrimary),
            at: CGPoint(x: size.width, y: waterLabelY + 8),
            anchor: .trailing
        )
    }

    private func drawCurve(context: GraphicsContext, layout: StockIntradayChartLayout) {
        guard let first = chart.points.first else { return }
        let start = layout.point(progress: first.progress, price: first.close)
        var path = Path()
        path.move(to: start)
        for point in chart.points.dropFirst() {
            path.addLine(to: layout.point(progress: point.progress, price: point.close))
        }
        if let last = chart.points.last {
            let end = layout.point(progress: last.progress, price: last.close)
            var area = path
            area.addLine(to: CGPoint(x: end.x, y: layout.plotRect.maxY))
            area.addLine(to: CGPoint(x: start.x, y: layout.plotRect.maxY))
            area.closeSubpath()
            context.fill(
                area,
                with: .linearGradient(
                    Gradient(colors: [palette.accent.opacity(0.22), palette.accent.opacity(0.015)]),
                    startPoint: CGPoint(x: 0, y: layout.plotRect.minY),
                    endPoint: CGPoint(x: 0, y: layout.plotRect.maxY)
                )
            )
            context.stroke(
                path,
                with: .color(palette.accentHover),
                style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
            )
            drawDot(context: context, at: end, color: palette.accentHover, diameter: 5)
        }
    }

    private func drawReviewMarkers(context: GraphicsContext, layout: StockIntradayChartLayout) {
        guard let markers = chart.reviewMarkers else { return }
        let values: [(Int?, String, Color, CGFloat)] = [
            (markers.buyIndex, "B", palette.positive, 14),
            (markers.sellIndex, "S", palette.negative, -14),
        ]
        for (index, label, color, offset) in values {
            guard let index, chart.points.indices.contains(index) else { continue }
            let source = chart.points[index]
            let anchor = layout.point(progress: source.progress, price: source.close)
            let center = CGPoint(
                x: min(max(anchor.x, layout.plotRect.minX + 10), layout.plotRect.maxX - 10),
                y: min(max(anchor.y + offset, layout.plotRect.minY + 10), layout.plotRect.maxY - 10)
            )
            let badge = CGRect(x: center.x - 9, y: center.y - 9, width: 18, height: 18)
            context.fill(
                Path(roundedRect: badge, cornerRadius: 5), with: .color(palette.surfaceElevated))
            context.stroke(
                Path(roundedRect: badge, cornerRadius: 5), with: .color(color.opacity(0.8)),
                lineWidth: 1)
            context.draw(
                Text(label).font(DesignTypography.metadata).foregroundStyle(color),
                at: center
            )
        }
    }

    private func drawInspection(
        context: GraphicsContext,
        point: IntradayChartPoint,
        layout: StockIntradayChartLayout
    ) {
        let position = layout.point(progress: point.progress, price: point.close)
        var crosshair = Path()
        crosshair.move(to: CGPoint(x: position.x, y: layout.plotRect.minY))
        crosshair.addLine(to: CGPoint(x: position.x, y: layout.plotRect.maxY))
        crosshair.move(to: CGPoint(x: layout.plotRect.minX, y: position.y))
        crosshair.addLine(to: CGPoint(x: layout.plotRect.maxX, y: position.y))
        context.stroke(
            crosshair,
            with: .color(palette.accent.opacity(0.6)),
            style: StrokeStyle(lineWidth: 0.75, dash: [3, 3])
        )
        drawDot(context: context, at: position, color: palette.textPrimary, diameter: 7)
    }

    private func drawDot(
        context: GraphicsContext, at point: CGPoint, color: Color, diameter: CGFloat
    ) {
        let dot = Path(
            ellipseIn: CGRect(
                x: point.x - diameter / 2,
                y: point.y - diameter / 2,
                width: diameter,
                height: diameter
            ))
        context.fill(dot, with: .color(color))
        context.stroke(dot, with: .color(palette.background), lineWidth: 1.5)
    }

    private func moveInspection(by offset: Int) -> KeyPress.Result {
        guard !chart.points.isEmpty else { return .ignored }
        let current = inspectedIndex ?? (offset < 0 ? chart.points.count : -1)
        inspectedIndex = min(max(current + offset, 0), chart.points.count - 1)
        return .handled
    }

    private var sessionDate: String {
        TradingCalendar.sessionDate(for: quote.marketTime, market: instrument.market)
    }

    private var statusText: String {
        switch status {
        case .previousSession: tr("最近交易日")
        case .stale: tr("缓存行情")
        case .loading: tr("刷新中")
        case .idle: tr("已载入")
        case .live: tr("当日行情")
        }
    }

    private var reviewExplanation: String {
        if chart.reviewMarkers?.buyIndex != nil {
            return tr("收盘复盘；B 与其后的 S 为本日最大正价差分钟收盘价，与昨收涨跌无关；不构成交易建议。")
        }
        return tr("收盘复盘；本日不存在先 B 后 S 的正价差，仅标注最高分钟收盘价 S；不构成交易建议。")
    }

    private var accessibilityReadout: String {
        "\(sessionDate)，\(timeText(displayedTime))，\(instrument.market.currencySymbol)\(priceText(displayedPrice))，\(InstrumentRowPresentation.percentText(displayedChange))"
    }

    private func priceText(_ price: Double) -> String {
        InstrumentRowPresentation.priceText(price)
    }

    private func axisPriceText(_ price: Double) -> String {
        let digits = min(max(Int(ceil(-log10(chart.high - chart.low))) + 1, price < 10 ? 3 : 2), 6)
        return String(format: "%.*f", digits, price)
    }

    private func timeText(_ time: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = instrument.market.timeZone
        let components = calendar.dateComponents([.hour, .minute], from: time)
        return String(format: "%02d:%02d", components.hour ?? 0, components.minute ?? 0)
    }
}
