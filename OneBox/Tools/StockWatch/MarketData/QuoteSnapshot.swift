import Foundation

enum QuoteSource: String, Codable, Sendable {
    case tencent
    case eastMoney
}

struct QuoteSnapshot: Equatable, Sendable {
    let instrumentID: InstrumentID
    let minuteBars: [MinuteBar]
    let dayOpen: Double
    let previousClose: Double
    let lastPrice: Double
    let marketTime: Date
    let receivedAt: Date
    let source: QuoteSource

    var changePercent: Double {
        guard previousClose > 0 else { return 0 }
        return (lastPrice - previousClose) / previousClose * 100
    }
}

enum QuoteSnapshotValidationError: LocalizedError, Equatable, Sendable {
    case instrumentMismatch(expected: InstrumentID, actual: InstrumentID)
    case invalidQuoteValues
    case invalidQuoteTime
    case minuteTimesNotStrictlyIncreasing
    case invalidMinuteValues
    case minuteOutsideQuoteSession

    var errorDescription: String? {
        switch self {
        case .instrumentMismatch(let expected, let actual):
            String(
                format: tr("行情标的 ID 不一致：应为 %@，实际为 %@"),
                expected.rawValue,
                actual.rawValue
            )
        case .invalidQuoteValues:
            tr("开盘价、昨收价和最新价必须为有限正数")
        case .invalidQuoteTime:
            tr("行情时间无效")
        case .minuteTimesNotStrictlyIncreasing:
            tr("分钟线时间必须严格递增且不能重复")
        case .invalidMinuteValues:
            tr("分钟线 OHLC 数据无效")
        case .minuteOutsideQuoteSession:
            tr("分钟线不属于行情交易日")
        }
    }
}

enum QuoteSnapshotValidator {
    static func validatedSessionDate(
        for snapshot: QuoteSnapshot,
        instrument: Instrument
    ) throws -> String {
        guard snapshot.instrumentID == instrument.id else {
            throw QuoteSnapshotValidationError.instrumentMismatch(
                expected: instrument.id,
                actual: snapshot.instrumentID
            )
        }
        let quoteValues = [snapshot.dayOpen, snapshot.previousClose, snapshot.lastPrice]
        guard quoteValues.allSatisfy({ $0.isFinite && $0 > 0 }) else {
            throw QuoteSnapshotValidationError.invalidQuoteValues
        }
        guard hasValidTimestamp(snapshot.marketTime), hasValidTimestamp(snapshot.receivedAt) else {
            throw QuoteSnapshotValidationError.invalidQuoteTime
        }

        let sessionDate = TradingCalendar.sessionDate(
            for: snapshot.marketTime,
            market: instrument.market
        )
        var previousTime: Date?
        for bar in snapshot.minuteBars {
            guard hasValidTimestamp(bar.time) else {
                throw QuoteSnapshotValidationError.invalidQuoteTime
            }
            if let previousTime, bar.time <= previousTime {
                throw QuoteSnapshotValidationError.minuteTimesNotStrictlyIncreasing
            }
            let values = [bar.open, bar.close, bar.high, bar.low]
            guard values.allSatisfy({ $0.isFinite && $0 > 0 }),
                bar.high >= max(bar.open, bar.close),
                bar.low <= min(bar.open, bar.close)
            else {
                throw QuoteSnapshotValidationError.invalidMinuteValues
            }
            guard
                TradingCalendar.sessionDate(for: bar.time, market: instrument.market) == sessionDate
            else {
                throw QuoteSnapshotValidationError.minuteOutsideQuoteSession
            }
            previousTime = bar.time
        }
        return sessionDate
    }

    private static func hasValidTimestamp(_ date: Date) -> Bool {
        let milliseconds = (date.timeIntervalSince1970 * 1_000).rounded()
        return milliseconds.isFinite
            && milliseconds > 0
            && milliseconds < Double(Int64.max)
    }
}
