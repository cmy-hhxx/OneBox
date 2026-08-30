import Foundation

struct Watchlist: Equatable, Sendable {
    private(set) var instruments: [Instrument]

    init(_ instruments: [Instrument] = []) {
        var seen = Set<InstrumentID>()
        self.instruments = instruments.filter { seen.insert($0.id).inserted }
    }

    mutating func add(_ instrument: Instrument) -> Bool {
        guard !instruments.contains(where: { $0.id == instrument.id }) else {
            return false
        }
        instruments.append(instrument)
        return true
    }

    mutating func remove(_ instrument: Instrument) {
        instruments.removeAll { $0.id == instrument.id }
    }

    mutating func move(from offsets: IndexSet, to destination: Int) {
        let sortedOffsets = offsets.sorted()
        let moving = sortedOffsets.map { instruments[$0] }
        for index in sortedOffsets.reversed() {
            instruments.remove(at: index)
        }
        let removedBeforeDestination = sortedOffsets.filter { $0 < destination }.count
        let insertionIndex = max(
            0,
            min(destination - removedBeforeDestination, instruments.count)
        )
        instruments.insert(contentsOf: moving, at: insertionIndex)
    }
}

enum WatchlistImportResult: Equatable, Sendable {
    case success(count: Int)
    case failure(String)

    var message: String {
        switch self {
        case .success(let count):
            String(format: tr("已导入 %d 个标的"), count)
        case .failure(let message):
            message
        }
    }
}
