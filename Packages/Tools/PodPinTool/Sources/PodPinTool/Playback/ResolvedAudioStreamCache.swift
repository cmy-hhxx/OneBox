import Foundation

/// Keeps recently resolved online streams in memory only. Stream URLs and
/// request headers can be short-lived and sensitive, so this cache is bounded,
/// never persisted, and is invalidated as soon as playback reports a failure.
actor ResolvedAudioStreamCache {
    private struct Key: Hashable, Sendable {
        let itemID: UUID
        let sourceURL: URL
    }

    private struct Entry: Sendable {
        let stream: ResolvedAudioStream
        let expiresAt: Date
        var lastAccessedAt: Date
    }

    private let capacity: Int
    private let timeToLive: TimeInterval
    private let now: @Sendable () -> Date
    private var entries: [Key: Entry] = [:]

    init(
        capacity: Int = 8,
        timeToLive: TimeInterval = 5 * 60,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.capacity = max(capacity, 1)
        self.timeToLive = max(timeToLive, 0)
        self.now = now
    }

    func stream(for item: AudioItem) -> ResolvedAudioStream? {
        let key = Key(itemID: item.id, sourceURL: item.sourceURL)
        guard var entry = entries[key] else { return nil }

        let timestamp = now()
        guard entry.expiresAt > timestamp else {
            entries.removeValue(forKey: key)
            return nil
        }

        entry.lastAccessedAt = timestamp
        entries[key] = entry
        return entry.stream
    }

    func insert(_ stream: ResolvedAudioStream, for item: AudioItem) {
        let timestamp = now()
        let key = Key(itemID: item.id, sourceURL: item.sourceURL)
        entries[key] = Entry(
            stream: stream,
            expiresAt: timestamp.addingTimeInterval(timeToLive),
            lastAccessedAt: timestamp
        )
        trimToCapacity()
    }

    func invalidate(item: AudioItem) {
        entries.removeValue(forKey: Key(itemID: item.id, sourceURL: item.sourceURL))
    }

    func invalidate(itemID: UUID) {
        entries = entries.filter { $0.key.itemID != itemID }
    }

    private func trimToCapacity() {
        while entries.count > capacity,
            let oldest = entries.min(by: { $0.value.lastAccessedAt < $1.value.lastAccessedAt })?.key
        {
            entries.removeValue(forKey: oldest)
        }
    }
}
