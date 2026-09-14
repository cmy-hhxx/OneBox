import Foundation

enum MonitorStatus: Equatable, Sendable {
    case idle
    case loading
    case live
    case previousSession
    case stale
}

struct MonitoredInstrument: Identifiable, Equatable, Sendable {
    var id: InstrumentID { instrument.id }

    let instrument: Instrument
    var quote: QuoteSnapshot?
    var chart: PreparedIntradayChart?
    var status: MonitorStatus
    var statusMessage: String?

    init(
        instrument: Instrument,
        quote: QuoteSnapshot?,
        status: MonitorStatus,
        statusMessage: String?
    ) {
        self.instrument = instrument
        self.quote = quote
        chart = quote.map { PreparedIntradayChart(instrument: instrument, quote: $0) }
        self.status = status
        self.statusMessage = statusMessage
    }
}
