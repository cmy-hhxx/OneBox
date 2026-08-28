import Foundation

enum TradingCalendar {
    static func sessionDate(for date: Date, market: Market) -> String {
        let components = calendar(for: market).dateComponents(
            [.year, .month, .day],
            from: date
        )
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    static func shouldShowAShareReviewMarkers(
        for quote: QuoteSnapshot,
        now: Date = Date()
    ) -> Bool {
        let currentSession = sessionDate(for: now, market: .aShare)
        let quoteSession = sessionDate(for: quote.marketTime, market: .aShare)
        if quoteSession < currentSession { return true }
        guard quoteSession == currentSession else { return false }

        let calendar = calendar(for: .aShare)
        let dayStart = calendar.startOfDay(for: now)
        guard
            let close = calendar.date(
                bySettingHour: 15,
                minute: 0,
                second: 0,
                of: dayStart
            )
        else { return false }
        return now >= close
    }

    private static func calendar(for market: Market) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = market.timeZone
        return calendar
    }
}
