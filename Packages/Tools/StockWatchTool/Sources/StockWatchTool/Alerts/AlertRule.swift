import Foundation

enum AlertDirection: String, Codable, Sendable {
    case rising
    case falling
}

enum AlertBasis: String, Codable, CaseIterable, Identifiable, Sendable {
    case percentage
    case targetPrice

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .percentage: tr("昨收涨跌幅")
        case .targetPrice: tr("目标价格")
        }
    }
}

enum AlertRule: Equatable, Sendable {
    case percentage(rising: Double, falling: Double)
    case targetPrice(rising: Double?, falling: Double?)
}

struct AlertConfiguration: Equatable, Sendable {
    var isEnabled: Bool
    var basis: AlertBasis
    var risingThreshold: Double
    var fallingThreshold: Double

    static let `default` = AlertConfiguration(
        isEnabled: true,
        basis: .percentage,
        risingThreshold: 3,
        fallingThreshold: 3
    )

    func rule(targets: PriceAlertTargets?) -> AlertRule? {
        switch basis {
        case .percentage:
            .percentage(rising: risingThreshold, falling: fallingThreshold)
        case .targetPrice:
            targets?.isEnabled == true ? targets?.rule : nil
        }
    }
}

struct PriceAlertTargets: Codable, Equatable, Sendable {
    var risingPrice: Double?
    var fallingPrice: Double?

    var isEnabled: Bool {
        risingPrice != nil || fallingPrice != nil
    }

    var rule: AlertRule {
        .targetPrice(
            rising: risingPrice,
            falling: fallingPrice
        )
    }
}

struct AlertSettingsSnapshot: Equatable, Sendable {
    var configuration: AlertConfiguration
    var priceTargets: [InstrumentID: PriceAlertTargets]

    static let `default` = AlertSettingsSnapshot(
        configuration: .default,
        priceTargets: [:]
    )
}

struct AlertEvent: Identifiable, Sendable {
    let id = UUID()
    let instrument: Instrument
    let changePercent: Double
    let lastPrice: Double
    let targetPrice: Double?
    let basis: AlertBasis
    let direction: AlertDirection
    let triggeredAt: Date
}
