import Foundation

enum SymbolNamespace: String, Codable, CaseIterable, Sendable {
    case shanghai = "sse"
    case shenzhen = "szse"
    case beijing = "bse"
    case hongKong = "hk"
    case unitedStates = "us"

    var market: Market {
        switch self {
        case .shanghai, .shenzhen, .beijing:
            .aShare
        case .hongKong:
            .hongKong
        case .unitedStates:
            .unitedStates
        }
    }

    var displayName: String {
        switch self {
        case .shanghai: tr("上交所")
        case .shenzhen: tr("深交所")
        case .beijing: tr("北交所")
        case .hongKong: tr("港交所")
        case .unitedStates: tr("美股")
        }
    }

    func normalize(symbol: String) -> String {
        market.normalize(symbol: symbol)
    }
}
