import OneBoxDesignSystem
import SwiftUI

enum MarketColorRole: Equatable, Sendable {
    case red
    case green
    case neutral
}

extension Market {
    /// 中国内地和香港采用红涨绿跌，美股采用绿涨红跌。
    func colorRole(isRising: Bool) -> MarketColorRole {
        switch self {
        case .aShare, .hongKong:
            isRising ? .red : .green
        case .unitedStates:
            isRising ? .green : .red
        }
    }

    func colorRole(forChange change: Double) -> MarketColorRole {
        if change > 0 { return colorRole(isRising: true) }
        if change < 0 { return colorRole(isRising: false) }
        return .neutral
    }
}

extension MarketColorRole {
    @MainActor
    func color(in palette: DesignPalette) -> Color {
        switch self {
        case .red:
            palette.negative
        case .green:
            palette.positive
        case .neutral:
            palette.textPrimary
        }
    }
}
