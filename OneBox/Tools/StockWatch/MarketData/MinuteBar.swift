import Foundation

struct MinuteBar: Identifiable, Codable, Equatable, Hashable, Sendable {
    var id: Date { time }

    let time: Date
    let open: Double
    let close: Double
    let high: Double
    let low: Double
}
