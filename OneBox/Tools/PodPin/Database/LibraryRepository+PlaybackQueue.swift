import Foundation
import GRDB

extension MarketDatabase {
    public func playbackQueue() throws -> [PlaybackQueueEntry] {
        try databaseQueue.read { database in
            try Self.fetchPlaybackQueue(in: database)
        }
    }

    /// Inserts or moves an item without allowing duplicate queue entries.
    @discardableResult
    public func enqueue(
        _ itemID: UUID,
        at placement: PlaybackQueuePlacement
    ) throws -> [PlaybackQueueEntry] {
        // `DatabaseWriter.write` is the repository's transaction boundary.
        // Keep every order mutation inside this one write closure.
        try databaseQueue.write { database in
            guard try Self.fetchItem(id: itemID, in: database) != nil else {
                throw MarketDatabaseError.itemNotFound(itemID)
            }
            var identifiers = try Self.queueItemIDs(in: database)
            identifiers.removeAll { $0 == itemID }
            switch placement {
            case .next:
                identifiers.insert(itemID, at: 0)
            case .last:
                identifiers.append(itemID)
            }
            try database.execute(
                sql:
                    "INSERT OR REPLACE INTO playback_queue (item_id, position, enqueued_at_ms) VALUES (?, ?, ?)",
                arguments: [Self.identifier(itemID), identifiers.count, Self.milliseconds(.now)]
            )
            try Self.replaceQueuePositions(with: identifiers, in: database)
            return try Self.fetchPlaybackQueue(in: database)
        }
    }

    @discardableResult
    public func moveQueueItem(_ itemID: UUID, to requestedPosition: Int) throws
        -> [PlaybackQueueEntry]
    {
        try databaseQueue.write { database in
            var identifiers = try Self.queueItemIDs(in: database)
            guard let currentPosition = identifiers.firstIndex(of: itemID) else {
                throw MarketDatabaseError.queueItemNotFound(itemID)
            }
            identifiers.remove(at: currentPosition)
            identifiers.insert(itemID, at: min(max(requestedPosition, 0), identifiers.count))
            try Self.replaceQueuePositions(with: identifiers, in: database)
            return try Self.fetchPlaybackQueue(in: database)
        }
    }

    @discardableResult
    public func removeQueueItem(_ itemID: UUID) throws -> [PlaybackQueueEntry] {
        try databaseQueue.write { database in
            try database.execute(
                sql: "DELETE FROM playback_queue WHERE item_id = ?",
                arguments: [Self.identifier(itemID)]
            )
            guard database.changesCount > 0 else {
                throw MarketDatabaseError.queueItemNotFound(itemID)
            }
            try Self.replaceQueuePositions(with: Self.queueItemIDs(in: database), in: database)
            return try Self.fetchPlaybackQueue(in: database)
        }
    }

    public func clearPlaybackQueue() throws {
        try databaseQueue.write { database in
            try database.execute(sql: "DELETE FROM playback_queue")
        }
    }

    /// Commits a resolved queue item as current playback in one transaction.
    /// Call this only after the stream or local file has been verified usable.
    public func activateQueueItem(_ itemID: UUID) throws -> AudioItem {
        try databaseQueue.write { database in
            guard let item = try Self.fetchItem(id: itemID, in: database) else {
                throw MarketDatabaseError.itemNotFound(itemID)
            }
            try database.execute(
                sql: "DELETE FROM playback_queue WHERE item_id = ?",
                arguments: [Self.identifier(itemID)]
            )
            guard database.changesCount > 0 else {
                throw MarketDatabaseError.queueItemNotFound(itemID)
            }
            try Self.replaceQueuePositions(with: Self.queueItemIDs(in: database), in: database)
            try database.execute(
                sql:
                    "UPDATE player_state SET current_item_id = ?, updated_at_ms = ? WHERE singleton = 1",
                arguments: [Self.identifier(itemID), Self.milliseconds(.now)]
            )
            return item
        }
    }

    static func fetchPlaybackQueue(in database: Database) throws -> [PlaybackQueueEntry] {
        try Row.fetchAll(
            database,
            sql: """
                SELECT audio_items.*, playback_queue.position, playback_queue.enqueued_at_ms
                FROM playback_queue
                JOIN audio_items ON audio_items.id = playback_queue.item_id
                ORDER BY playback_queue.position ASC
                """
        ).map { row in
            PlaybackQueueEntry(
                item: try item(from: row),
                position: row["position"],
                enqueuedAt: date(row["enqueued_at_ms"])
            )
        }
    }

    static func queueItemIDs(in database: Database) throws -> [UUID] {
        try String.fetchAll(
            database,
            sql: "SELECT item_id FROM playback_queue ORDER BY position ASC"
        ).compactMap(UUID.init(uuidString:))
    }

    static func replaceQueuePositions(with identifiers: [UUID], in database: Database) throws {
        for (position, itemID) in identifiers.enumerated() {
            try database.execute(
                sql: "UPDATE playback_queue SET position = ? WHERE item_id = ?",
                arguments: [position, identifier(itemID)]
            )
        }
    }
}
