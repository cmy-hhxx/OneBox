import Observation

@MainActor
@Observable
final class AlertPresentationSession {
    private(set) var settings: AlertSettingsSnapshot
    private(set) var activeAlert: AlertEvent?

    var configuration: AlertConfiguration {
        settings.configuration
    }

    var priceTargets: [InstrumentID: PriceAlertTargets] {
        settings.priceTargets
    }

    #if DEBUG || STOCKWATCH_BENCHMARK
        @ObservationIgnored
        private(set) var publicationCountForTesting = 0
    #endif

    init(
        settings: AlertSettingsSnapshot = .default,
        activeAlert: AlertEvent? = nil
    ) {
        self.settings = settings
        self.activeAlert = activeAlert
    }

    func publishSettings(_ settings: AlertSettingsSnapshot) {
        guard self.settings != settings else { return }
        self.settings = settings
        recordPublication()
    }

    func publishConfiguration(_ configuration: AlertConfiguration) {
        guard settings.configuration != configuration else { return }
        settings.configuration = configuration
        recordPublication()
    }

    func publishPriceTargets(_ priceTargets: [InstrumentID: PriceAlertTargets]) {
        guard settings.priceTargets != priceTargets else { return }
        settings.priceTargets = priceTargets
        recordPublication()
    }

    func publishActiveAlert(_ activeAlert: AlertEvent?) {
        guard self.activeAlert?.id != activeAlert?.id else { return }
        self.activeAlert = activeAlert
        recordPublication()
    }

    private func recordPublication() {
        #if DEBUG || STOCKWATCH_BENCHMARK
            publicationCountForTesting += 1
        #endif
    }
}
