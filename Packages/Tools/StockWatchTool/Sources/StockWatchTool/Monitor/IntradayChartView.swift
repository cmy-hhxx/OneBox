import OneBoxDesignSystem
import SwiftUI

struct ReviewMarkerInsets: Equatable {
    let horizontal: CGFloat
    let vertical: CGFloat

    static let zero = Self(horizontal: 0, vertical: 0)
}

struct ReviewMarkerLayout: Equatable {
    let markerPoint: CGPoint
    let labelPoint: CGPoint
    let fontSize: CGFloat
    let pointDiameter: CGFloat

    static func plotInsets(
        hasMarkers: Bool,
        isCompact: Bool
    ) -> ReviewMarkerInsets {
        guard hasMarkers else { return .zero }
        return ReviewMarkerInsets(
            horizontal: isCompact ? 5 : 6,
            vertical: isCompact ? 6 : 7
        )
    }

    init(
        canvasSize: CGSize,
        anchor: CGPoint,
        labelAbove: Bool,
        isCompact: Bool
    ) {
        fontSize = 12
        pointDiameter = 3

        let insets = Self.plotInsets(hasMarkers: true, isCompact: isCompact)
        let maximumAnchorX = max(canvasSize.width - insets.horizontal, insets.horizontal)
        let maximumAnchorY = max(canvasSize.height - insets.vertical, insets.vertical)
        markerPoint = CGPoint(
            x: min(max(anchor.x, insets.horizontal), maximumAnchorX),
            y: min(max(anchor.y, insets.vertical), maximumAnchorY)
        )

        let labelOffset: CGFloat = 7
        let labelBoundary = fontSize / 2 + 1
        let maximumLabelY = max(canvasSize.height - labelBoundary, labelBoundary)
        let preferredLabelY = markerPoint.y + (labelAbove ? -labelOffset : labelOffset)
        labelPoint = CGPoint(
            x: markerPoint.x,
            y: min(max(preferredLabelY, labelBoundary), maximumLabelY)
        )
    }
}

struct IntradayChartView: View {
    let chart: PreparedIntradayChart

    @Environment(\.designPalette) private var palette

    var body: some View {
        let plottedPoints = chart.points
        let closes = chart.closes
        let reviewMarkers = chart.reviewMarkers

        Canvas { context, size in
            guard !plottedPoints.isEmpty else { return }

            let range = max(chart.high - chart.low, Double.ulpOfOne)
            let isCompact = size.height < 52
            let markerInsets = ReviewMarkerLayout.plotInsets(
                hasMarkers: reviewMarkers != nil,
                isCompact: isCompact
            )
            let plotWidth = max(size.width - 2 * markerInsets.horizontal, 1)
            let plotHeight = max(size.height - 2 * markerInsets.vertical, 1)

            func coordinate(progress: Double, price: Double) -> CGPoint {
                let x =
                    markerInsets.horizontal
                    + plotWidth * CGFloat(min(max(progress, 0), 1))
                let normalized = (price - chart.low) / range
                let y = markerInsets.vertical + plotHeight * (1 - CGFloat(normalized))
                return CGPoint(x: x, y: y)
            }

            let waterY = coordinate(progress: 0, price: chart.previousClose).y
            var waterline = Path()
            waterline.move(to: CGPoint(x: markerInsets.horizontal, y: waterY))
            waterline.addLine(to: CGPoint(x: size.width - markerInsets.horizontal, y: waterY))
            context.stroke(
                waterline,
                with: .color(palette.border),
                style: StrokeStyle(lineWidth: 1, dash: [2, 4])
            )

            if let first = plottedPoints.first, let last = plottedPoints.last {
                var pricePath = Path()
                pricePath.move(to: coordinate(progress: first.progress, price: first.close))
                for point in plottedPoints.dropFirst() {
                    pricePath.addLine(to: coordinate(progress: point.progress, price: point.close))
                }
                var area = pricePath
                area.addLine(
                    to: CGPoint(
                        x: coordinate(progress: last.progress, price: last.close).x,
                        y: size.height - markerInsets.vertical))
                area.addLine(
                    to: CGPoint(
                        x: coordinate(progress: first.progress, price: first.close).x,
                        y: size.height - markerInsets.vertical))
                area.closeSubpath()
                context.fill(
                    area,
                    with: .linearGradient(
                        Gradient(colors: [
                            palette.accent.opacity(0.18), palette.accent.opacity(0.015),
                        ]),
                        startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
                context.stroke(
                    pricePath, with: .color(palette.accent),
                    style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
            }

            if let last = plottedPoints.last {
                let point = coordinate(progress: last.progress, price: last.close)
                context.fill(
                    Path(
                        ellipseIn: CGRect(
                            x: point.x - 2,
                            y: point.y - 2,
                            width: 4,
                            height: 4
                        )
                    ),
                    with: .color(palette.surface)
                )
                context.fill(
                    Path(
                        ellipseIn: CGRect(
                            x: point.x - 1.25,
                            y: point.y - 1.25,
                            width: 2.5,
                            height: 2.5
                        )
                    ),
                    with: .color(palette.accent)
                )
            }

            if let reviewMarkers {
                if let buyIndex = reviewMarkers.buyIndex {
                    drawReviewMarker(
                        context: context,
                        canvasSize: size,
                        at: coordinate(
                            progress: plottedPoints[buyIndex].progress,
                            price: closes[buyIndex]
                        ),
                        label: "B",
                        color: MarketColorRole.green.color(in: palette),
                        labelAbove: false,
                        isCompact: isCompact
                    )
                }
                if let sellIndex = reviewMarkers.sellIndex {
                    drawReviewMarker(
                        context: context,
                        canvasSize: size,
                        at: coordinate(
                            progress: plottedPoints[sellIndex].progress,
                            price: closes[sellIndex]
                        ),
                        label: "S",
                        color: MarketColorRole.red.color(in: palette),
                        labelAbove: true,
                        isCompact: isCompact
                    )
                }
            }
        }
        .accessibilityLabel(tr("分时曲线"))
        .accessibilityValue(
            reviewMarkers != nil ? reviewMarkersExplanation(for: reviewMarkers) : ""
        )
        .help(
            reviewMarkers != nil
                ? reviewMarkersExplanation(for: reviewMarkers)
                : tr("分时曲线")
        )
    }

    private func drawReviewMarker(
        context: GraphicsContext,
        canvasSize: CGSize,
        at point: CGPoint,
        label: String,
        color: Color,
        labelAbove: Bool,
        isCompact: Bool
    ) {
        let layout = ReviewMarkerLayout(
            canvasSize: canvasSize,
            anchor: point,
            labelAbove: labelAbove,
            isCompact: isCompact
        )
        context.fill(
            Path(
                ellipseIn: CGRect(
                    x: layout.markerPoint.x - layout.pointDiameter / 2,
                    y: layout.markerPoint.y - layout.pointDiameter / 2,
                    width: layout.pointDiameter,
                    height: layout.pointDiameter
                )
            ),
            with: .color(color)
        )
        context.fill(
            Path(
                roundedRect: CGRect(
                    x: layout.labelPoint.x - 5, y: layout.labelPoint.y - 6,
                    width: 10, height: 12), cornerRadius: 2),
            with: .color(palette.surface.opacity(0.94)))
        context.draw(
            Text(label)
                .font(DesignTypography.metadata)
                .foregroundStyle(color),
            at: layout.labelPoint,
            anchor: .center
        )
    }

    private func reviewMarkersExplanation(
        for reviewMarkers: IntradayReviewMarkerSelection?
    ) -> String {
        guard let reviewMarkers else {
            return tr("收盘复盘；本日未显示 B/S 标记；不构成交易建议。")
        }
        if reviewMarkers.buyIndex != nil {
            return tr("收盘复盘；B 与其后的 S 为本日最大正价差分钟收盘价，与昨收涨跌无关；不构成交易建议。")
        }
        return tr("收盘复盘；本日不存在先 B 后 S 的正价差，仅标注最高分钟收盘价 S；不构成交易建议。")
    }
}
