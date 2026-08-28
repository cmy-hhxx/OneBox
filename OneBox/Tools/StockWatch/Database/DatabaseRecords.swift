import Foundation

enum PriceAlertTargetViolation: Equatable, Sendable {
    case missingPrices
    case nonFinite(AlertDirection)
    case nonPositive(AlertDirection)
}

final class DatabaseCancellationToken: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func checkCancellation() throws {
        if isCancelled {
            throw CancellationError()
        }
    }
}

enum MarketDatabaseError: LocalizedError, Sendable {
    case applicationSupportUnavailable
    case unrecognizedDatabase(Int)
    case invalidSchema(String)
    case integrityCheckFailed
    case invalidNamespace(String)
    case invalidInstrumentID(expected: InstrumentID, stored: String)
    case invalidWatchlist
    case quoteInstrumentMismatch(expected: InstrumentID, actual: InstrumentID)
    case quoteSessionDateMismatch(instrumentID: InstrumentID, stored: String, derived: String)
    case invalidQuoteSource(String)
    case invalidAlertBasis(String)
    case invalidAlertConfiguration
    case invalidPriceAlertTargets(
        instrumentID: InstrumentID,
        violation: PriceAlertTargetViolation
    )
    case unsupportedSchemaVersion(Int)
    case invalidQuote(String)

    var errorDescription: String? {
        switch self {
        case .applicationSupportUnavailable:
            tr("无法访问应用支持目录")
        case .unrecognizedDatabase:
            tr("数据库不属于 OneBox 股票看盘")
        case .invalidSchema(let detail):
            String(format: tr("数据库结构无效：%@"), detail)
        case .integrityCheckFailed:
            tr("数据库完整性检查失败")
        case .invalidNamespace(let value):
            String(format: tr("数据库包含无效的标的代码域：%@"), value)
        case .invalidInstrumentID(let expected, let stored):
            String(
                format: tr("数据库标的 ID 不一致：应为 %@，实际为 %@"),
                expected.rawValue,
                stored
            )
        case .invalidWatchlist:
            tr("观察列表包含重复或无效的标的")
        case .quoteInstrumentMismatch(let expected, let actual):
            String(
                format: tr("行情标的 ID 不一致：应为 %@，实际为 %@"),
                expected.rawValue,
                actual.rawValue
            )
        case .quoteSessionDateMismatch(let instrumentID, let stored, let derived):
            String(
                format: tr("数据库行情交易日不一致：标的 %@ 存储为 %@，行情时间推导为 %@"),
                instrumentID.rawValue,
                stored,
                derived
            )
        case .invalidQuoteSource(let value):
            String(format: tr("数据库包含无效的行情来源：%@"), value)
        case .invalidAlertBasis(let value):
            String(format: tr("数据库包含无效的提醒依据：%@"), value)
        case .invalidAlertConfiguration:
            tr("提醒设置无效")
        case .invalidPriceAlertTargets(let instrumentID, let violation):
            switch violation {
            case .missingPrices:
                String(
                    format: tr("标的 %@ 的目标价至少需要设置一个方向"),
                    instrumentID.rawValue
                )
            case .nonFinite(let direction):
                String(
                    format: tr("标的 %@ 的%@目标价必须是有限数值"),
                    instrumentID.rawValue,
                    direction == .rising ? tr("上涨") : tr("下跌")
                )
            case .nonPositive(let direction):
                String(
                    format: tr("标的 %@ 的%@目标价必须大于零"),
                    instrumentID.rawValue,
                    direction == .rising ? tr("上涨") : tr("下跌")
                )
            }
        case .unsupportedSchemaVersion(let version):
            String(format: tr("不支持的数据库结构版本：%d"), version)
        case .invalidQuote(let message):
            String(format: tr("行情快照无效：%@"), message)
        }
    }
}
