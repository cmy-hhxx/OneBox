import Foundation

struct DownloadProgressSnapshot: Equatable, Sendable {
    let fraction: Double?
    let bytesPerSecond: Double?

    static let indeterminate = DownloadProgressSnapshot(fraction: nil, bytesPerSecond: nil)
    static let complete = DownloadProgressSnapshot(fraction: 1, bytesPerSecond: nil)

    init(fraction: Double?, bytesPerSecond: Double?) {
        self.fraction = fraction.flatMap { value in
            value.isFinite ? min(max(value, 0), 1) : nil
        }
        self.bytesPerSecond = bytesPerSecond.flatMap { value in
            value.isFinite && value >= 0 ? value : nil
        }
    }

    func scaled(to upperBound: Double) -> DownloadProgressSnapshot {
        DownloadProgressSnapshot(
            fraction: fraction.map { $0 * min(max(upperBound, 0), 1) },
            bytesPerSecond: bytesPerSecond
        )
    }
}

struct DownloadSpeedSampler: Sendable {
    private var previousBytes: Int64?
    private var previousTime: TimeInterval?

    mutating func sample(completedBytes: Int64, at time: TimeInterval) -> Double? {
        guard completedBytes >= 0, time.isFinite else { return nil }
        defer {
            previousBytes = completedBytes
            previousTime = time
        }
        guard let previousBytes, let previousTime,
            completedBytes >= previousBytes,
            time - previousTime >= 0.1
        else { return nil }
        return Double(completedBytes - previousBytes) / (time - previousTime)
    }
}
