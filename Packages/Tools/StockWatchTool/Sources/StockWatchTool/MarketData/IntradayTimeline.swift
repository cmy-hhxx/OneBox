import Foundation

struct IntradayTimeline: Sendable {
    private let calendar: Calendar
    private let sessions: [Session]
    private let totalDuration: Double

    init(market: Market) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = market.timeZone
        self.calendar = calendar
        sessions = Self.sessions(for: market)
        totalDuration = sessions.reduce(0.0) { total, session in
            total + session.end - session.start
        }
    }

    func progress(at date: Date) -> Double? {
        let minute = minuteOfDay(for: date)
        var elapsed = 0.0

        for session in sessions {
            if minute < session.start {
                return nil
            }
            if minute <= session.end {
                return (elapsed + minute - session.start) / totalDuration
            }
            elapsed += session.end - session.start
        }

        return nil
    }

    static func progress(at date: Date, market: Market) -> Double? {
        IntradayTimeline(market: market).progress(at: date)
    }

    private func minuteOfDay(for date: Date) -> Double {
        let components = calendar.dateComponents([.hour, .minute, .second], from: date)
        return Double((components.hour ?? 0) * 60 + (components.minute ?? 0))
            + Double(components.second ?? 0) / 60
    }

    private static func sessions(for market: Market) -> [Session] {
        switch market {
        case .aShare:
            [
                Session(start: 9 * 60 + 30, end: 11 * 60 + 30),
                Session(start: 13 * 60, end: 15 * 60),
            ]
        case .hongKong:
            [
                Session(start: 9 * 60 + 30, end: 12 * 60),
                Session(start: 13 * 60, end: 16 * 60),
            ]
        case .unitedStates:
            [Session(start: 9 * 60 + 30, end: 16 * 60)]
        }
    }

    private struct Session: Sendable {
        let start: Double
        let end: Double
    }
}
