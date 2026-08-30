import Foundation

struct AlertEvaluator {
    private var hasTriggeredRising = false
    private var hasTriggeredFalling = false

    mutating func evaluate(
        changePercent: Double,
        lastPrice: Double,
        rule: AlertRule
    ) -> AlertDirection? {
        switch rule {
        case .percentage(let rising, let falling):
            evaluatePercentage(
                changePercent: changePercent,
                risingThreshold: rising,
                fallingThreshold: falling
            )
        case .targetPrice(let rising, let falling):
            evaluateTargetPrice(
                lastPrice: lastPrice,
                risingTarget: rising,
                fallingTarget: falling
            )
        }
    }

    private mutating func evaluatePercentage(
        changePercent: Double,
        risingThreshold: Double,
        fallingThreshold: Double,
        hysteresis: Double = 0.15
    ) -> AlertDirection? {
        if changePercent < risingThreshold - hysteresis,
            changePercent > -fallingThreshold + hysteresis
        {
            hasTriggeredRising = false
            hasTriggeredFalling = false
        }
        if changePercent >= risingThreshold, !hasTriggeredRising {
            hasTriggeredRising = true
            return .rising
        }
        if changePercent <= -fallingThreshold, !hasTriggeredFalling {
            hasTriggeredFalling = true
            return .falling
        }
        return nil
    }

    private mutating func evaluateTargetPrice(
        lastPrice: Double,
        risingTarget: Double?,
        fallingTarget: Double?,
        hysteresisRatio: Double = 0.0015
    ) -> AlertDirection? {
        let isBelowRisingRearm =
            risingTarget.map {
                lastPrice < $0 * (1 - hysteresisRatio)
            } ?? true
        let isAboveFallingRearm =
            fallingTarget.map {
                lastPrice > $0 * (1 + hysteresisRatio)
            } ?? true
        if isBelowRisingRearm, isAboveFallingRearm {
            hasTriggeredRising = false
            hasTriggeredFalling = false
        }

        if let risingTarget,
            lastPrice >= risingTarget,
            !hasTriggeredRising
        {
            hasTriggeredRising = true
            return .rising
        }
        if let fallingTarget,
            lastPrice <= fallingTarget,
            !hasTriggeredFalling
        {
            hasTriggeredFalling = true
            return .falling
        }
        return nil
    }
}
