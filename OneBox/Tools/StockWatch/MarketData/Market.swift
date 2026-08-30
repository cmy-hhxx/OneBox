import Foundation

enum Market: String, Codable, CaseIterable, Sendable {
    case aShare
    case hongKong
    case unitedStates

    var displayName: String {
        switch self {
        case .aShare: tr("A股")
        case .hongKong: tr("港股")
        case .unitedStates: tr("美股")
        }
    }

    var currencySymbol: String {
        switch self {
        case .aShare: "¥"
        case .hongKong: "HK$"
        case .unitedStates: "$"
        }
    }

    var timeZone: TimeZone {
        switch self {
        case .aShare:
            TimeZone(identifier: "Asia/Shanghai")!
        case .hongKong:
            TimeZone(identifier: "Asia/Hong_Kong")!
        case .unitedStates:
            TimeZone(identifier: "America/New_York")!
        }
    }

    func normalize(symbol: String) -> String {
        let trimmed = symbol.trimmingCharacters(in: .whitespacesAndNewlines)
        return self == .unitedStates ? trimmed.uppercased() : trimmed
    }
}
