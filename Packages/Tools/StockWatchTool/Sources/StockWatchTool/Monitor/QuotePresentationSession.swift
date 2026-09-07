import Foundation
import Observation

struct QuotePresentationSnapshot: Equatable, Sendable {
    var monitoredInstruments: [InstrumentID: MonitoredInstrument]
    var lastRefresh: Date?
    var sourceError: String?

    static let empty = QuotePresentationSnapshot(
        monitoredInstruments: [:],
        lastRefresh: nil,
        sourceError: nil
    )
}

@MainActor
@Observable
final class QuotePresentationSession {
    private(set) var snapshot: QuotePresentationSnapshot

    #if DEBUG || STOCKWATCH_BENCHMARK
        @ObservationIgnored
        private(set) var publicationCountForTesting = 0
    #endif

    init(snapshot: QuotePresentationSnapshot = .empty) {
        self.snapshot = snapshot
    }

    func publish(_ snapshot: QuotePresentationSnapshot) {
        self.snapshot = snapshot
        #if DEBUG || STOCKWATCH_BENCHMARK
            publicationCountForTesting += 1
        #endif
    }

    func update(_ transform: (inout QuotePresentationSnapshot) -> Void) {
        var updated = snapshot
        transform(&updated)
        publish(updated)
    }
}
