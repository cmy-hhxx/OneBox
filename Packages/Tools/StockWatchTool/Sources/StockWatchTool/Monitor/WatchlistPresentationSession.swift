import Observation

@MainActor
@Observable
final class WatchlistPresentationSession {
    private(set) var watchlist: Watchlist
    private(set) var isMutating: Bool

    var instruments: [Instrument] {
        watchlist.instruments
    }

    #if DEBUG || STOCKWATCH_BENCHMARK
        @ObservationIgnored
        private(set) var publicationCountForTesting = 0
    #endif

    init(
        watchlist: Watchlist = Watchlist(),
        isMutating: Bool = false
    ) {
        self.watchlist = watchlist
        self.isMutating = isMutating
    }

    func publish(_ watchlist: Watchlist) {
        guard self.watchlist != watchlist else { return }
        self.watchlist = watchlist
        recordPublication()
    }

    func setIsMutating(_ isMutating: Bool) {
        guard self.isMutating != isMutating else { return }
        self.isMutating = isMutating
        recordPublication()
    }

    private func recordPublication() {
        #if DEBUG || STOCKWATCH_BENCHMARK
            publicationCountForTesting += 1
        #endif
    }
}
