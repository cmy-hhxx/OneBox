import Foundation
import GRDB

enum MarketDatabaseError: Error, Equatable, Sendable {
    case applicationSupportUnavailable
    case folderNotFound(UUID)
    case itemNotFound(UUID)
    case emptyFolderName
    case duplicateFolderName(parentID: UUID?, name: String)
    case cannotModifySystemFolder(UUID)
    case cannotDeleteNonEmptyFolder(UUID)
    case cannotMoveFolderIntoItself(UUID)
    case cannotMoveFolderIntoDescendant(UUID, UUID)
    case invalidContentID
    case invalidTitle
    case invalidSourceURL
    case invalidDuration
    case invalidRelativePath
    case invalidDownloadState
    case duplicateAudioItem(platform: AudioPlatform, contentID: String)
    case queueItemNotFound(UUID)
}

/// The stable position of an item in a folder page. The ID tie-breaker keeps
/// pagination deterministic when several items share the same import time.
struct ItemCursor: Equatable, Hashable, Sendable {
    /// The value of the collection's primary descending sort key. Folder and
    /// recent-import collections use the import time; recent playback uses the
    /// last-played time.
    let sortValueMilliseconds: Int64
    let itemID: UUID

    init(sortValueMilliseconds: Int64, itemID: UUID) {
        self.sortValueMilliseconds = sortValueMilliseconds
        self.itemID = itemID
    }

    /// Compatibility initializer for existing folder-page callers.
    init(importedAtMilliseconds: Int64, itemID: UUID) {
        self.init(sortValueMilliseconds: importedAtMilliseconds, itemID: itemID)
    }

    var importedAtMilliseconds: Int64 { sortValueMilliseconds }
}

struct ItemPage: Equatable, Sendable {
    let items: [AudioItem]
    let nextCursor: ItemCursor?
}

/// A single, explicit user archive operation. Its destination is authoritative
/// for both new and duplicate content, while metadata refreshes use their own
/// command and therefore cannot silently move an item.
struct ArchiveRequest: Sendable {
    let items: [AudioItem]
    let destinationFolderID: UUID
}

enum ArchiveItemResult: Equatable, Sendable {
    case inserted(AudioItem)
    case moved(AudioItem, fromFolderID: UUID)
    case refreshed(AudioItem)

    var item: AudioItem {
        switch self {
        case .inserted(let item), .moved(let item, _), .refreshed(let item):
            item
        }
    }
}

struct ArchiveResult: Equatable, Sendable {
    let destinationFolderID: UUID
    let itemResults: [ArchiveItemResult]

    init(destinationFolderID: UUID, itemResults: [ArchiveItemResult]) {
        self.destinationFolderID = destinationFolderID
        self.itemResults = itemResults
    }

    var items: [AudioItem] {
        itemResults.map(\.item)
    }
}

/// SQLite-backed source of truth for PodPin's folders, audio items, and current playback item.
///
/// The actor serializes all database access so callers can safely use it from SwiftUI and
/// background import/playback work without coordinating their own transactions.
actor MarketDatabase {
    static let defaultFileName = "podpin.sqlite"
    static let applicationSupportFolderName = "PodPin"

    let databaseQueue: DatabaseQueue
    nonisolated let databasePath: String

    private init(databaseQueue: DatabaseQueue, databasePath: String) throws {
        self.databaseQueue = databaseQueue
        self.databasePath = databasePath
        try DatabaseSchema.initialize(databaseQueue)
    }

    static func inMemory() throws -> MarketDatabase {
        try MarketDatabase(
            databaseQueue: DatabaseQueue(configuration: configuration()),
            databasePath: ":memory:"
        )
    }

    static func open(atPath path: String) throws -> MarketDatabase {
        try MarketDatabase(
            databaseQueue: DatabaseQueue(path: path, configuration: configuration()),
            databasePath: path
        )
    }

    static func open(at url: URL) throws -> MarketDatabase {
        try open(atPath: url.path)
    }

    static func openInApplicationSupport(
        fileManager: FileManager = .default
    ) throws -> MarketDatabase {
        let folderURL = try PodPinLibraryLocation.rootURL(fileManager: fileManager)
        return try open(at: folderURL.appendingPathComponent(defaultFileName))
    }

    static func applicationSupportDatabaseURL(
        fileManager: FileManager = .default
    ) -> URL? {
        try? PodPinLibraryLocation.rootURL(fileManager: fileManager)
            .appendingPathComponent(defaultFileName, isDirectory: false)
    }

    func close() throws {
        try databaseQueue.close()
    }

    func inbox() throws -> LibraryFolder {
        guard let inbox = try folder(id: LibraryFolder.inboxID) else {
            throw MarketDatabaseError.folderNotFound(LibraryFolder.inboxID)
        }
        return inbox
    }

    func folder(id: UUID) throws -> LibraryFolder? {
        try databaseQueue.read { database in
            try Self.fetchFolder(id: id, in: database)
        }
    }

    func listFolders(parentID: UUID? = nil) throws -> [LibraryFolder] {
        try databaseQueue.read { database in
            if let parentID {
                guard try Self.folderExists(parentID, in: database) else {
                    throw MarketDatabaseError.folderNotFound(parentID)
                }
                return try Self.fetchFolders(parentID: parentID, in: database)
            }
            return try Self.fetchFolders(parentID: nil, in: database)
        }
    }

    func allFolders() throws -> [LibraryFolder] {
        try databaseQueue.read { database in
            try Self.fetchAllFolders(in: database)
        }
    }

    @discardableResult
    func createFolder(named name: String, parentID: UUID? = nil) throws -> LibraryFolder {
        let normalizedName = try Self.normalizedFolderName(name)
        let folder = LibraryFolder(parentID: parentID, name: normalizedName)
        try databaseQueue.write { database in
            try Self.requireParent(parentID, in: database)
            try Self.requireUniqueFolderName(
                normalizedName,
                parentID: parentID,
                excluding: nil,
                in: database
            )
            try Self.insert(folder, in: database)
        }
        return folder
    }

    @discardableResult
    func renameFolder(_ id: UUID, to name: String) throws -> LibraryFolder {
        let normalizedName = try Self.normalizedFolderName(name)
        return try databaseQueue.write { database in
            guard var folder = try Self.fetchFolder(id: id, in: database) else {
                throw MarketDatabaseError.folderNotFound(id)
            }
            guard !folder.isSystemFolder else {
                throw MarketDatabaseError.cannotModifySystemFolder(id)
            }
            try Self.requireUniqueFolderName(
                normalizedName,
                parentID: folder.parentID,
                excluding: id,
                in: database
            )
            folder.name = normalizedName
            try database.execute(
                sql: "UPDATE library_folders SET name = ?, normalized_name = ? WHERE id = ?",
                arguments: [normalizedName, Self.foldedName(normalizedName), Self.identifier(id)]
            )
            return folder
        }
    }

    @discardableResult
    func moveFolder(_ id: UUID, toParentID parentID: UUID?) throws -> LibraryFolder {
        try databaseQueue.write { database in
            guard var folder = try Self.fetchFolder(id: id, in: database) else {
                throw MarketDatabaseError.folderNotFound(id)
            }
            guard !folder.isSystemFolder else {
                throw MarketDatabaseError.cannotModifySystemFolder(id)
            }
            guard parentID != id else {
                throw MarketDatabaseError.cannotMoveFolderIntoItself(id)
            }
            try Self.requireParent(parentID, in: database)
            if let parentID, try Self.isDescendant(parentID, of: id, in: database) {
                throw MarketDatabaseError.cannotMoveFolderIntoDescendant(id, parentID)
            }
            try Self.requireUniqueFolderName(
                folder.name,
                parentID: parentID,
                excluding: id,
                in: database
            )
            folder.parentID = parentID
            try database.execute(
                sql: "UPDATE library_folders SET parent_id = ?, parent_key = ? WHERE id = ?",
                arguments: [
                    parentID.map(Self.identifier),
                    Self.parentKey(parentID),
                    Self.identifier(id),
                ]
            )
            return folder
        }
    }

    func deleteFolder(_ id: UUID) throws {
        try databaseQueue.write { database in
            guard let folder = try Self.fetchFolder(id: id, in: database) else {
                throw MarketDatabaseError.folderNotFound(id)
            }
            guard !folder.isSystemFolder else {
                throw MarketDatabaseError.cannotModifySystemFolder(id)
            }
            let containsChildren =
                try Bool.fetchOne(
                    database,
                    sql: "SELECT EXISTS(SELECT 1 FROM library_folders WHERE parent_id = ?)",
                    arguments: [Self.identifier(id)]
                ) ?? false
            let containsItems =
                try Bool.fetchOne(
                    database,
                    sql: "SELECT EXISTS(SELECT 1 FROM audio_items WHERE folder_id = ?)",
                    arguments: [Self.identifier(id)]
                ) ?? false
            guard !containsChildren, !containsItems else {
                throw MarketDatabaseError.cannotDeleteNonEmptyFolder(id)
            }
            try database.execute(
                sql: "DELETE FROM library_folders WHERE id = ?",
                arguments: [Self.identifier(id)]
            )
        }
    }

    func item(id: UUID) throws -> AudioItem? {
        try databaseQueue.read { database in
            try Self.fetchItem(id: id, in: database)
        }
    }

    func item(platform: AudioPlatform, contentID: String) throws -> AudioItem? {
        let contentID = try Self.normalizedContentID(contentID)
        return try databaseQueue.read { database in
            try Self.fetchItem(platform: platform, contentID: contentID, in: database)
        }
    }

    func listItems(in folderID: UUID = LibraryFolder.inboxID) throws -> [AudioItem] {
        try databaseQueue.read { database in
            try Self.requireParent(folderID, in: database)
            return try Self.fetchItems(folderID: folderID, in: database)
        }
    }

    /// Returns one stable page from a folder. Callers intentionally receive a
    /// small snapshot rather than an unbounded list so rendering a large local
    /// library never requires an all-item database read.
    func listItemPage(
        in folderID: UUID = LibraryFolder.inboxID,
        after cursor: ItemCursor? = nil,
        limit: Int = 200
    ) throws -> ItemPage {
        let pageLimit = min(max(limit, 1), 500)
        return try databaseQueue.read { database in
            try Self.requireParent(folderID, in: database)
            let candidates = try Self.fetchItemPage(
                folderID: folderID,
                after: cursor,
                limit: pageLimit + 1,
                in: database
            )
            let items = Array(candidates.prefix(pageLimit))
            let nextCursor =
                candidates.count > pageLimit
                ? items.last.map {
                    ItemCursor(
                        importedAtMilliseconds: Self.milliseconds($0.importedAt),
                        itemID: $0.id
                    )
                }
                : nil
            return ItemPage(items: items, nextCursor: nextCursor)
        }
    }

    func listAllItems() throws -> [AudioItem] {
        try databaseQueue.read { database in
            try Self.fetchAllItems(in: database)
        }
    }

    /// Marks any download left in progress by a previous process as retryable.
    /// The caller owns removing the matching media directories after receiving
    /// these identifiers; keeping that filesystem work outside SQLite means a
    /// failed cleanup can be retried safely on the next launch.
    func recoverInterruptedDownloads() throws -> [UUID] {
        try databaseQueue.write { database in
            let identifiers = try String.fetchAll(
                database,
                sql: "SELECT id FROM audio_items WHERE download_state = 'downloading'"
            ).compactMap(UUID.init(uuidString:))
            guard !identifiers.isEmpty else { return [] }

            try database.execute(
                sql: """
                    UPDATE audio_items
                    SET storage_kind = 'online', download_state = 'not_requested',
                        local_media_relative_path = NULL, updated_at_ms = ?
                    WHERE download_state = 'downloading'
                    """,
                arguments: [Self.milliseconds(.now)]
            )
            return identifiers
        }
    }

    @discardableResult
    func insertItem(_ item: AudioItem) throws -> AudioItem {
        let normalizedItem = try Self.validated(item)
        try databaseQueue.write { database in
            try Self.requireParent(normalizedItem.folderID, in: database)
            if try Self.fetchItem(
                platform: normalizedItem.platform,
                contentID: normalizedItem.contentID,
                in: database
            ) != nil {
                throw MarketDatabaseError.duplicateAudioItem(
                    platform: normalizedItem.platform,
                    contentID: normalizedItem.contentID
                )
            }
            try Self.insert(normalizedItem, in: database)
        }
        return normalizedItem
    }

    /// Archives a selection in one transaction. Existing matching content is
    /// moved to the explicit destination while retaining its identity, playback
    /// progress, import date, and any completed offline media path.
    @discardableResult
    func archive(_ request: ArchiveRequest) throws -> ArchiveResult {
        let normalizedItems = try Self.validatedArchiveItems(request)
        return try databaseQueue.write { database in
            try Self.requireParent(request.destinationFolderID, in: database)
            let results = try normalizedItems.map { item -> ArchiveItemResult in
                guard
                    let existing = try Self.fetchItem(
                        platform: item.platform,
                        contentID: item.contentID,
                        in: database
                    )
                else {
                    try Self.insert(item, in: database)
                    return .inserted(item)
                }

                let archived = Self.merge(
                    existing: existing,
                    incoming: item,
                    folderID: request.destinationFolderID
                )
                try Self.update(archived, in: database)
                if existing.folderID != request.destinationFolderID {
                    return .moved(archived, fromFolderID: existing.folderID)
                }
                return .refreshed(archived)
            }
            return ArchiveResult(
                destinationFolderID: request.destinationFolderID,
                itemResults: results
            )
        }
    }

    /// Refreshes source metadata without changing the user's archive choice.
    @discardableResult
    func refreshMetadata(_ item: AudioItem) throws -> AudioItem {
        let normalizedItem = try Self.validated(item)
        return try databaseQueue.write { database in
            guard
                let existing = try Self.fetchItem(
                    platform: normalizedItem.platform,
                    contentID: normalizedItem.contentID,
                    in: database
                )
            else {
                throw MarketDatabaseError.itemNotFound(normalizedItem.id)
            }
            let refreshed = Self.merge(
                existing: existing,
                incoming: normalizedItem,
                folderID: existing.folderID
            )
            try Self.update(refreshed, in: database)
            return refreshed
        }
    }

    @discardableResult
    func updateItem(_ item: AudioItem) throws -> AudioItem {
        let normalizedItem = try Self.validated(item)
        return try databaseQueue.write { database in
            guard let existing = try Self.fetchItem(id: normalizedItem.id, in: database) else {
                throw MarketDatabaseError.itemNotFound(normalizedItem.id)
            }
            try Self.requireParent(normalizedItem.folderID, in: database)
            if let conflicting = try Self.fetchItem(
                platform: normalizedItem.platform,
                contentID: normalizedItem.contentID,
                in: database
            ), conflicting.id != existing.id {
                throw MarketDatabaseError.duplicateAudioItem(
                    platform: normalizedItem.platform,
                    contentID: normalizedItem.contentID
                )
            }
            let saved = AudioItem(
                id: normalizedItem.id,
                platform: normalizedItem.platform,
                contentID: normalizedItem.contentID,
                sourceURL: normalizedItem.sourceURL,
                title: normalizedItem.title,
                author: normalizedItem.author,
                artworkRelativePath: normalizedItem.artworkRelativePath,
                duration: normalizedItem.duration,
                folderID: normalizedItem.folderID,
                storageKind: normalizedItem.storageKind,
                downloadState: normalizedItem.downloadState,
                localMediaRelativePath: normalizedItem.localMediaRelativePath,
                playbackPosition: Self.clampedPlaybackPosition(
                    normalizedItem.playbackPosition,
                    duration: normalizedItem.duration
                ),
                lastPlayedAt: normalizedItem.lastPlayedAt,
                importedAt: existing.importedAt,
                updatedAt: .now
            )
            try Self.update(saved, in: database)
            return saved
        }
    }

    /// Updates auxiliary artwork without rewriting independently changing media
    /// state such as an in-flight offline download.
    @discardableResult
    func updateArtworkPath(
        for id: UUID,
        relativePath: String?
    ) throws -> AudioItem {
        let normalizedPath = try relativePath.map(Self.validatedRelativePath)
        return try databaseQueue.write { database in
            guard var item = try Self.fetchItem(id: id, in: database) else {
                throw MarketDatabaseError.itemNotFound(id)
            }
            item.artworkRelativePath = normalizedPath
            item.updatedAt = .now
            try database.execute(
                sql: """
                    UPDATE audio_items
                    SET artwork_relative_path = ?, updated_at_ms = ?
                    WHERE id = ?
                    """,
                arguments: [
                    normalizedPath,
                    Self.milliseconds(item.updatedAt),
                    Self.identifier(id),
                ]
            )
            return item
        }
    }

    @discardableResult
    func moveItem(_ id: UUID, toFolderID folderID: UUID) throws -> AudioItem {
        try databaseQueue.write { database in
            guard var item = try Self.fetchItem(id: id, in: database) else {
                throw MarketDatabaseError.itemNotFound(id)
            }
            try Self.requireParent(folderID, in: database)
            item.folderID = folderID
            item.updatedAt = .now
            try database.execute(
                sql: "UPDATE audio_items SET folder_id = ?, updated_at_ms = ? WHERE id = ?",
                arguments: [
                    Self.identifier(folderID),
                    Self.milliseconds(item.updatedAt),
                    Self.identifier(id),
                ]
            )
            return item
        }
    }

    @discardableResult
    func updateDownloadState(
        for id: UUID,
        state: AudioDownloadState,
        localMediaRelativePath: String? = nil,
        duration: TimeInterval? = nil
    ) throws -> AudioItem {
        try databaseQueue.write { database in
            guard var item = try Self.fetchItem(id: id, in: database) else {
                throw MarketDatabaseError.itemNotFound(id)
            }
            let normalizedPath = try localMediaRelativePath.map(Self.validatedRelativePath)
            switch state {
            case .notRequested:
                guard normalizedPath == nil else { throw MarketDatabaseError.invalidDownloadState }
                item.storageKind = .online
                item.downloadState = .notRequested
                item.localMediaRelativePath = nil
            case .downloading, .failed:
                guard normalizedPath == nil else { throw MarketDatabaseError.invalidDownloadState }
                item.storageKind = .offline
                item.downloadState = state
                item.localMediaRelativePath = nil
            case .available:
                guard let normalizedPath else { throw MarketDatabaseError.invalidDownloadState }
                if let duration {
                    guard duration.isFinite, duration > 0 else {
                        throw MarketDatabaseError.invalidDuration
                    }
                    item.duration = duration
                }
                item.playbackPosition = Self.clampedPlaybackPosition(
                    item.playbackPosition,
                    duration: item.duration
                )
                item.storageKind = .offline
                item.downloadState = .available
                item.localMediaRelativePath = normalizedPath
            }
            item.updatedAt = .now
            try Self.update(item, in: database)
            return item
        }
    }

    /// Completes a download without exposing an unrelated generic update path.
    @discardableResult
    func completeDownload(
        for id: UUID,
        localMediaRelativePath: String,
        duration: TimeInterval
    ) throws -> AudioItem {
        try updateDownloadState(
            for: id,
            state: .available,
            localMediaRelativePath: localMediaRelativePath,
            duration: duration
        )
    }

    @discardableResult
    func updatePlaybackPosition(
        for id: UUID,
        position: TimeInterval,
        listeningHistory: ListeningHistory? = nil,
        lastPlayedAt: Date? = .now
    ) throws -> AudioItem {
        try databaseQueue.write { database in
            guard var item = try Self.fetchItem(id: id, in: database) else {
                throw MarketDatabaseError.itemNotFound(id)
            }
            item.playbackPosition = Self.clampedPlaybackPosition(position, duration: item.duration)
            if let listeningHistory {
                item.listeningHistory = ListeningHistory(intervals: listeningHistory.intervals)
            }
            item.lastPlayedAt = lastPlayedAt
            item.updatedAt = .now
            try database.execute(
                sql: """
                    UPDATE audio_items
                    SET playback_position_ms = ?, listening_history_json = ?,
                        last_played_at_ms = ?, updated_at_ms = ?
                    WHERE id = ?
                    """,
                arguments: [
                    Self.milliseconds(item.playbackPosition),
                    try Self.encodedListeningHistory(item.listeningHistory),
                    item.lastPlayedAt.map(Self.milliseconds),
                    Self.milliseconds(item.updatedAt),
                    Self.identifier(id),
                ]
            )
            return item
        }
    }

    func deleteItem(_ id: UUID) throws {
        try databaseQueue.write { database in
            guard try Self.fetchItem(id: id, in: database) != nil else {
                throw MarketDatabaseError.itemNotFound(id)
            }
            try database.execute(
                sql: "DELETE FROM audio_items WHERE id = ?",
                arguments: [Self.identifier(id)]
            )
        }
    }

    func currentPlaybackItem() throws -> AudioItem? {
        try databaseQueue.read { database in
            guard
                let identifier = try String.fetchOne(
                    database,
                    sql: "SELECT current_item_id FROM player_state WHERE singleton = 1"
                ), let id = UUID(uuidString: identifier)
            else {
                return nil
            }
            return try Self.fetchItem(id: id, in: database)
        }
    }

    func setCurrentPlaybackItem(_ id: UUID?) throws {
        try databaseQueue.write { database in
            if let id, try Self.fetchItem(id: id, in: database) == nil {
                throw MarketDatabaseError.itemNotFound(id)
            }
            try database.execute(
                sql:
                    "UPDATE player_state SET current_item_id = ?, updated_at_ms = ? WHERE singleton = 1",
                arguments: [id.map(Self.identifier), Self.milliseconds(.now)]
            )
        }
    }
}

extension MarketDatabase {
    static func validatedArchiveItems(_ request: ArchiveRequest) throws -> [AudioItem] {
        let normalizedItems = try request.items.map { item in
            var archived = item
            archived.folderID = request.destinationFolderID
            return try validated(archived)
        }
        var identities = Set<String>()
        for item in normalizedItems {
            let identity = "\(item.platform.rawValue)\u{1F}\(item.contentID)"
            guard identities.insert(identity).inserted else {
                throw MarketDatabaseError.duplicateAudioItem(
                    platform: item.platform,
                    contentID: item.contentID
                )
            }
        }
        return normalizedItems
    }

    static func configuration() -> Configuration {
        var configuration = Configuration()
        configuration.prepareDatabase { database in
            try database.execute(sql: "PRAGMA foreign_keys = ON")
            try database.execute(sql: "PRAGMA busy_timeout = 5000")
        }
        return configuration
    }

    static func fetchFolder(id: UUID, in database: Database) throws -> LibraryFolder? {
        guard
            let row = try Row.fetchOne(
                database,
                sql: """
                    SELECT id, parent_id, name, system_kind, created_at_ms
                    FROM library_folders WHERE id = ?
                    """,
                arguments: [identifier(id)]
            )
        else {
            return nil
        }
        return try folder(from: row)
    }

    static func fetchFolders(parentID: UUID?, in database: Database) throws -> [LibraryFolder] {
        let sql: String
        let arguments: StatementArguments
        if let parentID {
            sql = """
                SELECT id, parent_id, name, system_kind, created_at_ms
                FROM library_folders WHERE parent_id = ?
                ORDER BY system_kind = 'inbox' DESC, name COLLATE NOCASE ASC, id ASC
                """
            arguments = [identifier(parentID)]
        } else {
            sql = """
                SELECT id, parent_id, name, system_kind, created_at_ms
                FROM library_folders WHERE parent_id IS NULL
                ORDER BY system_kind = 'inbox' DESC, name COLLATE NOCASE ASC, id ASC
                """
            arguments = []
        }
        return try Row.fetchAll(database, sql: sql, arguments: arguments).map(folder(from:))
    }

    static func fetchAllFolders(in database: Database) throws -> [LibraryFolder] {
        try Row.fetchAll(
            database,
            sql: """
                SELECT id, parent_id, name, system_kind, created_at_ms
                FROM library_folders
                ORDER BY created_at_ms ASC, id ASC
                """
        ).map(folder(from:))
    }

    static func fetchItem(id: UUID, in database: Database) throws -> AudioItem? {
        guard
            let row = try Row.fetchOne(
                database,
                sql: "SELECT * FROM audio_items WHERE id = ?",
                arguments: [identifier(id)]
            )
        else {
            return nil
        }
        return try item(from: row)
    }

    static func fetchItem(
        platform: AudioPlatform,
        contentID: String,
        in database: Database
    ) throws -> AudioItem? {
        guard
            let row = try Row.fetchOne(
                database,
                sql: "SELECT * FROM audio_items WHERE platform = ? AND content_id = ?",
                arguments: [platform.rawValue, contentID]
            )
        else {
            return nil
        }
        return try item(from: row)
    }

    static func fetchItems(folderID: UUID, in database: Database) throws -> [AudioItem] {
        try Row.fetchAll(
            database,
            sql:
                "SELECT * FROM audio_items WHERE folder_id = ? ORDER BY imported_at_ms DESC, id DESC",
            arguments: [identifier(folderID)]
        ).map(item(from:))
    }

    static func fetchItemPage(
        folderID: UUID,
        after cursor: ItemCursor?,
        limit: Int,
        in database: Database
    ) throws -> [AudioItem] {
        if let cursor {
            return try Row.fetchAll(
                database,
                sql: """
                    SELECT * FROM audio_items
                    WHERE folder_id = ?
                        AND (imported_at_ms < ? OR (imported_at_ms = ? AND id < ?))
                    ORDER BY imported_at_ms DESC, id DESC
                    LIMIT ?
                    """,
                arguments: [
                    identifier(folderID),
                    cursor.importedAtMilliseconds,
                    cursor.importedAtMilliseconds,
                    identifier(cursor.itemID),
                    limit,
                ]
            ).map(item(from:))
        }
        return try Row.fetchAll(
            database,
            sql: """
                SELECT * FROM audio_items
                WHERE folder_id = ?
                ORDER BY imported_at_ms DESC, id DESC
                LIMIT ?
                """,
            arguments: [identifier(folderID), limit]
        ).map(item(from:))
    }

    static func fetchAllItems(in database: Database) throws -> [AudioItem] {
        try Row.fetchAll(
            database,
            sql: "SELECT * FROM audio_items ORDER BY imported_at_ms DESC, id ASC"
        ).map(item(from:))
    }

    static func insert(_ folder: LibraryFolder, in database: Database) throws {
        try database.execute(
            sql: """
                INSERT INTO library_folders (
                    id, parent_id, parent_key, name, normalized_name, system_kind, created_at_ms
                ) VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
            arguments: [
                identifier(folder.id),
                folder.parentID.map(identifier),
                parentKey(folder.parentID),
                folder.name,
                foldedName(folder.name),
                folder.systemKind.rawValue,
                milliseconds(folder.createdAt),
            ]
        )
    }

    static func insert(_ item: AudioItem, in database: Database) throws {
        try database.execute(
            sql: """
                INSERT INTO audio_items (
                    id, platform, content_id, source_url, title, author, artwork_relative_path,
                    duration_ms, folder_id, storage_kind, download_state, local_media_relative_path,
                    playback_position_ms, listening_history_json, last_played_at_ms,
                    imported_at_ms, updated_at_ms
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
            arguments: try itemArguments(item)
        )
    }

    static func update(_ item: AudioItem, in database: Database) throws {
        try database.execute(
            sql: """
                UPDATE audio_items SET
                    platform = ?, content_id = ?, source_url = ?, title = ?, author = ?,
                    artwork_relative_path = ?, duration_ms = ?, folder_id = ?, storage_kind = ?,
                    download_state = ?, local_media_relative_path = ?, playback_position_ms = ?,
                    listening_history_json = ?, last_played_at_ms = ?, updated_at_ms = ?
                WHERE id = ?
                """,
            arguments: [
                item.platform.rawValue,
                item.contentID,
                item.sourceURL.absoluteString,
                item.title,
                item.author,
                item.artworkRelativePath,
                item.duration.map(milliseconds),
                identifier(item.folderID),
                item.storageKind.rawValue,
                item.downloadState.rawValue,
                item.localMediaRelativePath,
                milliseconds(item.playbackPosition),
                try encodedListeningHistory(item.listeningHistory),
                item.lastPlayedAt.map(milliseconds),
                milliseconds(item.updatedAt),
                identifier(item.id),
            ]
        )
    }

    static func itemArguments(_ item: AudioItem) throws -> StatementArguments {
        [
            identifier(item.id),
            item.platform.rawValue,
            item.contentID,
            item.sourceURL.absoluteString,
            item.title,
            item.author,
            item.artworkRelativePath,
            item.duration.map(milliseconds),
            identifier(item.folderID),
            item.storageKind.rawValue,
            item.downloadState.rawValue,
            item.localMediaRelativePath,
            milliseconds(item.playbackPosition),
            try encodedListeningHistory(item.listeningHistory),
            item.lastPlayedAt.map(milliseconds),
            milliseconds(item.importedAt),
            milliseconds(item.updatedAt),
        ]
    }

    static func folder(from row: Row) throws -> LibraryFolder {
        guard let id = UUID(uuidString: row["id"] as String),
            let systemKind = LibraryFolderSystemKind(rawValue: row["system_kind"] as String)
        else {
            throw DatabaseDecodingError.invalidStoredValue
        }
        let parentID = try optionalUUID(row["parent_id"])
        let createdAt: Int64 = row["created_at_ms"]
        return LibraryFolder(
            id: id,
            parentID: parentID,
            name: row["name"],
            systemKind: systemKind,
            createdAt: date(createdAt)
        )
    }

    static func item(from row: Row) throws -> AudioItem {
        guard let id = UUID(uuidString: row["id"] as String),
            let platform = AudioPlatform(rawValue: row["platform"] as String),
            let storageKind = AudioStorageKind(rawValue: row["storage_kind"] as String),
            let downloadState = AudioDownloadState(rawValue: row["download_state"] as String),
            let sourceURL = URL(string: row["source_url"] as String)
        else {
            throw DatabaseDecodingError.invalidStoredValue
        }
        let durationMilliseconds: Int64? = row["duration_ms"]
        let lastPlayedMilliseconds: Int64? = row["last_played_at_ms"]
        let importedMilliseconds: Int64 = row["imported_at_ms"]
        let updatedMilliseconds: Int64 = row["updated_at_ms"]
        let playbackMilliseconds: Int64 = row["playback_position_ms"]
        let listeningHistoryJSON: String = row["listening_history_json"]
        return AudioItem(
            id: id,
            platform: platform,
            contentID: row["content_id"],
            sourceURL: sourceURL,
            title: row["title"],
            author: row["author"],
            artworkRelativePath: row["artwork_relative_path"],
            duration: durationMilliseconds.map(seconds),
            folderID: try requiredUUID(row["folder_id"]),
            storageKind: storageKind,
            downloadState: downloadState,
            localMediaRelativePath: row["local_media_relative_path"],
            playbackPosition: seconds(playbackMilliseconds),
            listeningHistory: try decodedListeningHistory(listeningHistoryJSON),
            lastPlayedAt: lastPlayedMilliseconds.map(date),
            importedAt: date(importedMilliseconds),
            updatedAt: date(updatedMilliseconds)
        )
    }

    static func folderExists(_ id: UUID, in database: Database) throws -> Bool {
        try Bool.fetchOne(
            database,
            sql: "SELECT EXISTS(SELECT 1 FROM library_folders WHERE id = ?)",
            arguments: [identifier(id)]
        ) ?? false
    }

    static func requireParent(_ id: UUID?, in database: Database) throws {
        guard let id else { return }
        guard try folderExists(id, in: database) else {
            throw MarketDatabaseError.folderNotFound(id)
        }
    }

    static func requireUniqueFolderName(
        _ name: String,
        parentID: UUID?,
        excluding id: UUID?,
        in database: Database
    ) throws {
        let existingIdentifier = try String.fetchOne(
            database,
            sql: """
                SELECT id FROM library_folders
                WHERE parent_key = ? AND normalized_name = ?
                LIMIT 1
                """,
            arguments: [parentKey(parentID), foldedName(name)]
        )
        guard existingIdentifier == nil || existingIdentifier == id.map(identifier) else {
            throw MarketDatabaseError.duplicateFolderName(parentID: parentID, name: name)
        }
    }

    static func isDescendant(_ candidate: UUID, of ancestor: UUID, in database: Database) throws
        -> Bool
    {
        var next: UUID? = candidate
        var visited = Set<UUID>()
        while let id = next {
            guard visited.insert(id).inserted else { return true }
            if id == ancestor { return true }
            next = try fetchFolder(id: id, in: database)?.parentID
        }
        return false
    }

    static func merge(
        existing: AudioItem,
        incoming: AudioItem,
        folderID: UUID
    ) -> AudioItem {
        let shouldUpgradeToOffline =
            existing.storageKind == .online
            && incoming.storageKind == .offline
            && incoming.downloadState == .available
        let useIncomingStorage = shouldUpgradeToOffline || existing.storageKind == .online
        let storageKind = useIncomingStorage ? incoming.storageKind : existing.storageKind
        let downloadState = useIncomingStorage ? incoming.downloadState : existing.downloadState
        let localMediaRelativePath =
            useIncomingStorage
            ? incoming.localMediaRelativePath
            : existing.localMediaRelativePath
        let duration = incoming.duration ?? existing.duration
        return AudioItem(
            id: existing.id,
            platform: existing.platform,
            contentID: existing.contentID,
            sourceURL: incoming.sourceURL,
            title: incoming.title,
            author: incoming.author,
            artworkRelativePath: incoming.artworkRelativePath ?? existing.artworkRelativePath,
            duration: duration,
            folderID: folderID,
            storageKind: storageKind,
            downloadState: downloadState,
            localMediaRelativePath: localMediaRelativePath,
            playbackPosition: clampedPlaybackPosition(
                existing.playbackPosition, duration: duration),
            listeningHistory: existing.listeningHistory,
            lastPlayedAt: existing.lastPlayedAt,
            importedAt: existing.importedAt,
            updatedAt: .now
        )
    }

    static func validated(_ item: AudioItem) throws -> AudioItem {
        let contentID = try normalizedContentID(item.contentID)
        let title = try normalizedTitle(item.title)
        guard let scheme = item.sourceURL.scheme?.lowercased(),
            ["http", "https"].contains(scheme),
            item.sourceURL.host != nil
        else {
            throw MarketDatabaseError.invalidSourceURL
        }
        guard item.duration.map({ $0.isFinite && $0 >= 0 }) ?? true,
            item.playbackPosition.isFinite
        else {
            throw MarketDatabaseError.invalidDuration
        }
        let artworkPath = try item.artworkRelativePath.map(validatedRelativePath)
        let mediaPath = try item.localMediaRelativePath.map(validatedRelativePath)
        let position = clampedPlaybackPosition(item.playbackPosition, duration: item.duration)
        var result = item
        result.contentID = contentID
        result.title = title
        result.author = normalizedOptionalText(item.author)
        result.artworkRelativePath = artworkPath
        result.localMediaRelativePath = mediaPath
        result.playbackPosition = position
        result.listeningHistory = ListeningHistory(intervals: item.listeningHistory.intervals)

        switch (result.storageKind, result.downloadState, result.localMediaRelativePath) {
        case (.online, .notRequested, nil), (.offline, .downloading, nil), (.offline, .failed, nil),
            (.offline, .available, .some):
            return result
        default:
            throw MarketDatabaseError.invalidDownloadState
        }
    }

    static func normalizedFolderName(_ name: String) throws -> String {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw MarketDatabaseError.emptyFolderName }
        return name
    }

    static func normalizedContentID(_ contentID: String) throws -> String {
        let contentID = contentID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !contentID.isEmpty else { throw MarketDatabaseError.invalidContentID }
        return contentID
    }

    static func normalizedTitle(_ title: String) throws -> String {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw MarketDatabaseError.invalidTitle }
        return title
    }

    static func normalizedOptionalText(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func validatedRelativePath(_ path: String) throws -> String {
        let path = path.trimmingCharacters(in: .whitespacesAndNewlines)
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !path.isEmpty,
            !path.hasPrefix("/"),
            !components.contains(".."),
            !components.contains(where: { $0.isEmpty })
        else {
            throw MarketDatabaseError.invalidRelativePath
        }
        return path
    }

    static func clampedPlaybackPosition(_ position: TimeInterval, duration: TimeInterval?)
        -> TimeInterval
    {
        let lowerBound = max(0, position)
        guard let duration else { return lowerBound }
        return min(lowerBound, duration)
    }

    static func encodedListeningHistory(_ history: ListeningHistory) throws -> String {
        let data = try JSONEncoder().encode(history)
        guard let value = String(data: data, encoding: .utf8) else {
            throw DatabaseDecodingError.invalidStoredValue
        }
        return value
    }

    static func decodedListeningHistory(_ value: String) throws -> ListeningHistory {
        guard let data = value.data(using: .utf8) else {
            throw DatabaseDecodingError.invalidStoredValue
        }
        let decoded = try JSONDecoder().decode(ListeningHistory.self, from: data)
        return ListeningHistory(intervals: decoded.intervals)
    }

    static func foldedName(_ name: String) -> String {
        name.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
    }

    static func parentKey(_ parentID: UUID?) -> String {
        parentID.map(identifier) ?? ""
    }

    static func identifier(_ id: UUID) -> String {
        id.uuidString.lowercased()
    }

    static func milliseconds(_ date: Date) -> Int64 {
        milliseconds(date.timeIntervalSince1970)
    }

    static func milliseconds(_ seconds: TimeInterval) -> Int64 {
        Int64((seconds * 1_000).rounded())
    }

    static func seconds(_ milliseconds: Int64) -> TimeInterval {
        TimeInterval(milliseconds) / 1_000
    }

    static func date(_ milliseconds: Int64) -> Date {
        Date(timeIntervalSince1970: seconds(milliseconds))
    }

    static func optionalUUID(_ value: String?) throws -> UUID? {
        guard let value else { return nil }
        guard let id = UUID(uuidString: value) else {
            throw DatabaseDecodingError.invalidStoredValue
        }
        return id
    }

    static func requiredUUID(_ value: String?) throws -> UUID {
        guard let id = try optionalUUID(value) else {
            throw DatabaseDecodingError.invalidStoredValue
        }
        return id
    }
}

private enum DatabaseDecodingError: Error {
    case invalidStoredValue
}
