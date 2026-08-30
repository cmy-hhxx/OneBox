import Combine
import Foundation

enum PlaybackQueuePlacement: Sendable {
    case next
    case last
}

/// A durable upcoming-playback entry. The current item is intentionally not a
/// queue entry, matching the familiar “Up Next” mental model.
struct PlaybackQueueEntry: Identifiable, Equatable, Sendable {
    let item: AudioItem
    let position: Int
    let enqueuedAt: Date

    var id: UUID { item.id }

    init(item: AudioItem, position: Int, enqueuedAt: Date) {
        self.item = item
        self.position = position
        self.enqueuedAt = enqueuedAt
    }
}

@MainActor
final class PlaybackQueueSession: ObservableObject {
    @Published private(set) var entries: [PlaybackQueueEntry] = []
    @Published private(set) var errorMessage: String?

    var count: Int { entries.count }
    var nextItem: AudioItem? { entries.first?.item }

    func replaceEntries(_ entries: [PlaybackQueueEntry]) {
        self.entries = entries
    }

    func presentError(_ message: String?) {
        errorMessage = message
    }
}

/// A deep module for queue presentation and persistence. Callers only express
/// their intent; it owns reloads, ordering, and the single queue state snapshot.
@MainActor
final class PlaybackQueueController {
    let session = PlaybackQueueSession()

    private var repository: MarketDatabase?

    func configure(repository: MarketDatabase) {
        self.repository = repository
    }

    func reload() async throws {
        guard let repository else { return }
        session.replaceEntries(try await repository.playbackQueue())
    }

    func enqueue(_ itemID: UUID, at placement: PlaybackQueuePlacement) async throws {
        guard let repository else { return }
        session.replaceEntries(try await repository.enqueue(itemID, at: placement))
        session.presentError(nil)
    }

    func move(_ itemID: UUID, to position: Int) async throws {
        guard let repository else { return }
        session.replaceEntries(try await repository.moveQueueItem(itemID, to: position))
    }

    func remove(_ itemID: UUID) async throws {
        guard let repository else { return }
        session.replaceEntries(try await repository.removeQueueItem(itemID))
    }

    func clear() async throws {
        guard let repository else { return }
        try await repository.clearPlaybackQueue()
        session.replaceEntries([])
        session.presentError(nil)
    }

    /// Removes an entry only after the audio controller reports that it has
    /// accepted the replacement item. This keeps a failed head retryable.
    func activateAfterPlaybackIsReady(_ itemID: UUID) async throws -> AudioItem {
        guard let repository else { throw PlaybackQueueControllerError.unconfigured }
        let item = try await repository.activateQueueItem(itemID)
        session.replaceEntries(try await repository.playbackQueue())
        session.presentError(nil)
        return item
    }

    func retainFailedHead(message: String) {
        session.presentError(message)
    }
}

enum PlaybackQueueControllerError: LocalizedError {
    case unconfigured

    var errorDescription: String? {
        switch self {
        case .unconfigured: "播放队列尚未准备完成。"
        }
    }
}
