import Observation

@MainActor
@Observable
final class AlertThresholdPresentationSession {
    enum Field: Equatable {
        case rising
        case falling
    }

    var risingThreshold: Double
    var fallingThreshold: Double

    private(set) var activeField: Field?

    init(configuration: AlertConfiguration) {
        risingThreshold = configuration.risingThreshold
        fallingThreshold = configuration.fallingThreshold
    }

    func synchronize(with configuration: AlertConfiguration) {
        guard activeField == nil else { return }
        risingThreshold = configuration.risingThreshold
        fallingThreshold = configuration.fallingThreshold
    }

    func editingChanged(
        _ isEditing: Bool,
        field: Field,
        currentConfiguration: AlertConfiguration,
        commit: (AlertConfiguration) -> Void
    ) {
        if isEditing {
            activeField = field
            return
        }
        guard activeField == field else { return }
        activeField = nil

        var updated = currentConfiguration
        switch field {
        case .rising:
            updated.risingThreshold = risingThreshold
        case .falling:
            updated.fallingThreshold = fallingThreshold
        }
        synchronize(with: updated)
        guard updated != currentConfiguration else { return }
        commit(updated)
    }
}
