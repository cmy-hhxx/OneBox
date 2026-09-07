import Observation

@MainActor
@Observable
final class DiagnosticsPresentationSession {
    let databasePath: String
    private(set) var storageError: String?
    private(set) var quoteBarCount: Int

    #if DEBUG || STOCKWATCH_BENCHMARK
        @ObservationIgnored
        private(set) var publicationCountForTesting = 0
    #endif

    init(
        databasePath: String,
        storageError: String? = nil,
        quoteBarCount: Int = 0
    ) {
        self.databasePath = databasePath
        self.storageError = storageError
        self.quoteBarCount = quoteBarCount
    }

    func publishStorageError(_ storageError: String?) {
        guard self.storageError != storageError else { return }
        self.storageError = storageError
        recordPublication()
    }

    func publishQuoteBarCount(_ quoteBarCount: Int) {
        guard self.quoteBarCount != quoteBarCount else { return }
        self.quoteBarCount = quoteBarCount
        recordPublication()
    }

    private func recordPublication() {
        #if DEBUG || STOCKWATCH_BENCHMARK
            publicationCountForTesting += 1
        #endif
    }
}
