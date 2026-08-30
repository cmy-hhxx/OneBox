import Foundation

enum MonitorStatus: Equatable, Sendable {
    case idle
    case loading
    case live
    case stale
}

struct MonitoredInstrument: Identifiable, Equatable, Sendable {
    var id: InstrumentID { instrument.id }

    let instrument: Instrument
    var quote: QuoteSnapshot?
    var status: MonitorStatus
    var statusMessage: String?
}
