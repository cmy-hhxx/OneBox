import Foundation

public struct ListenedInterval: Codable, Equatable, Hashable, Sendable {
    public let start: TimeInterval
    public let end: TimeInterval

    public init(start: TimeInterval, end: TimeInterval) {
        self.start = start
        self.end = end
    }
}

/// The union of media-time intervals that actually passed through audible
/// playback. Seeking resets sampling, so skipped gaps remain visible.
public struct ListeningHistory: Codable, Equatable, Hashable, Sendable {
    public private(set) var intervals: [ListenedInterval]

    public init(intervals: [ListenedInterval] = []) {
        self.intervals = Self.normalized(intervals)
    }

    public mutating func record(
        from start: TimeInterval,
        to end: TimeInterval,
        duration: TimeInterval?
    ) {
        guard start.isFinite, end.isFinite else { return }
        let upperBound =
            duration.flatMap { value in
                value.isFinite && value > 0 ? value : nil
            } ?? .greatestFiniteMagnitude
        let interval = ListenedInterval(
            start: min(max(start, 0), upperBound),
            end: min(max(end, 0), upperBound)
        )
        guard interval.end - interval.start >= 0.05 else { return }
        intervals = Self.normalized(intervals + [interval])
    }

    public func listenedFraction(duration: TimeInterval) -> Double {
        guard duration.isFinite, duration > 0 else { return 0 }
        let listened = intervals.reduce(0) { partial, interval in
            partial + max(0, min(interval.end, duration) - min(max(interval.start, 0), duration))
        }
        return min(max(listened / duration, 0), 1)
    }

    public func isComplete(duration: TimeInterval) -> Bool {
        guard duration.isFinite, duration > 0 else { return false }
        let unheardDuration = duration * (1 - listenedFraction(duration: duration))
        return unheardDuration < 0.05
    }

    private static func normalized(_ intervals: [ListenedInterval]) -> [ListenedInterval] {
        let sorted = intervals.compactMap { interval -> ListenedInterval? in
            guard interval.start.isFinite, interval.end.isFinite else { return nil }
            let start = max(0, min(interval.start, interval.end))
            let end = max(0, max(interval.start, interval.end))
            guard end - start >= 0.05 else { return nil }
            return ListenedInterval(start: start, end: end)
        }.sorted {
            $0.start == $1.start ? $0.end < $1.end : $0.start < $1.start
        }

        return sorted.reduce(into: []) { merged, interval in
            guard let last = merged.last else {
                merged.append(interval)
                return
            }
            if interval.start <= last.end + 0.01 {
                merged[merged.count - 1] = ListenedInterval(
                    start: last.start,
                    end: max(last.end, interval.end)
                )
            } else {
                merged.append(interval)
            }
        }
    }
}
