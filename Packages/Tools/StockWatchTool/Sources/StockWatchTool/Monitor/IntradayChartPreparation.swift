import Foundation

struct IntradayChartPoint: Equatable, Sendable {
    let progress: Double
    let close: Double
}

enum IntradaySegmentColoring {
    static func roles(
        closes: [Double],
        market: Market
    ) -> [MarketColorRole] {
        guard closes.count > 1 else { return [] }

        return zip(closes, closes.dropFirst()).map { previous, current in
            market.colorRole(forChange: current - previous)
        }
    }
}

struct IntradayChartPreparation: Equatable, Sendable {
    let points: [IntradayChartPoint]
    let low: Double
    let high: Double
    let reviewMarkers: IntradayReviewMarkerSelection?

    init(
        points sourcePoints: [MinuteBar],
        market: Market,
        dayOpen: Double,
        previousClose: Double,
        showReviewMarkers: Bool
    ) {
        let timeline = IntradayTimeline(market: market)
        var points: [IntradayChartPoint] = []
        points.reserveCapacity(sourcePoints.count)

        var minimum = min(dayOpen, previousClose)
        var maximum = max(dayOpen, previousClose)
        var lowestClose: Double?
        var highestClose: Double?
        var lowestIndex = 0
        var highestIndex = 0
        var bestProfit = 0.0
        var bestBuyIndex: Int?
        var bestSellIndex: Int?

        for point in sourcePoints {
            guard let progress = timeline.progress(at: point.time) else { continue }

            let index = points.count
            let close = point.close
            points.append(IntradayChartPoint(progress: progress, close: close))
            minimum = min(minimum, close)
            maximum = max(maximum, close)

            guard showReviewMarkers else { continue }

            guard let currentLowestClose = lowestClose else {
                lowestClose = close
                highestClose = close
                continue
            }

            let profit = close - currentLowestClose
            if profit > bestProfit {
                bestProfit = profit
                bestBuyIndex = lowestIndex
                bestSellIndex = index
            }
            if close < currentLowestClose {
                lowestClose = close
                lowestIndex = index
            }
            if let currentHighestClose = highestClose, close > currentHighestClose {
                highestClose = close
                highestIndex = index
            }
        }

        self.points = points
        let padding = max(
            (maximum - minimum) * 0.14,
            max(abs(previousClose) * 0.0008, 0.01)
        )
        low = minimum - padding
        high = maximum + padding
        guard showReviewMarkers,
            points.count > 1,
            let lowestClose,
            let highestClose,
            lowestClose < highestClose
        else {
            reviewMarkers = nil
            return
        }

        if bestProfit > 0,
            let bestBuyIndex,
            let bestSellIndex
        {
            reviewMarkers = IntradayReviewMarkerSelection(
                buyIndex: bestBuyIndex,
                sellIndex: bestSellIndex
            )
        } else {
            reviewMarkers = IntradayReviewMarkerSelection(
                buyIndex: nil,
                sellIndex: highestIndex
            )
        }
    }
}

/// Immutable chart data prepared once when a quote enters the monitor store.
/// Canvas rendering only projects these points into its current size.
struct PreparedIntradayChart: Equatable, Sendable {
    let points: [IntradayChartPoint]
    let closes: [Double]
    let segmentRoles: [MarketColorRole]
    let low: Double
    let high: Double
    let previousClose: Double
    let fallbackColorRole: MarketColorRole
    let reviewMarkers: IntradayReviewMarkerSelection?

    init(instrument: Instrument, quote: QuoteSnapshot) {
        let showsReviewMarkers =
            instrument.market == .aShare
            && TradingCalendar.shouldShowAShareReviewMarkers(for: quote)
        let preparation = IntradayChartPreparation(
            points: quote.minuteBars,
            market: instrument.market,
            dayOpen: quote.dayOpen,
            previousClose: quote.previousClose,
            showReviewMarkers: showsReviewMarkers
        )

        points = preparation.points
        closes = preparation.points.map(\.close)
        segmentRoles = IntradaySegmentColoring.roles(
            closes: closes,
            market: instrument.market
        )
        low = preparation.low
        high = preparation.high
        previousClose = quote.previousClose
        fallbackColorRole = instrument.market.colorRole(forChange: quote.changePercent)
        reviewMarkers = preparation.reviewMarkers
    }
}
