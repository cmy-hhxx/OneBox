import Foundation
import GRDB

extension MarketDatabase {
    /// Reads one bounded, stable page from a smart collection or a folder.
    /// Every collection shares the same cursor contract: descending primary
    /// timestamp with the item ID as a deterministic tie-breaker.
    public func listItemPage(
        in collection: LibraryCollection,
        after cursor: ItemCursor? = nil,
        limit: Int = 200
    ) throws -> ItemPage {
        let pageLimit = min(max(limit, 1), 500)
        return try databaseQueue.read { database in
            if case .folder(let folderID) = collection {
                try Self.requireParent(folderID, in: database)
            }
            let candidates = try Self.fetchItemPage(
                collection: collection,
                after: cursor,
                limit: pageLimit + 1,
                in: database
            )
            let items = Array(candidates.prefix(pageLimit))
            let nextCursor =
                candidates.count > pageLimit
                ? items.last.map {
                    ItemCursor(
                        sortValueMilliseconds: Self.collectionSortValue(for: $0, in: collection),
                        itemID: $0.id
                    )
                }
                : nil
            return ItemPage(items: items, nextCursor: nextCursor)
        }
    }

    static func fetchItemPage(
        collection: LibraryCollection,
        after cursor: ItemCursor?,
        limit: Int,
        in database: Database
    ) throws -> [AudioItem] {
        let specification: (whereClause: String, arguments: StatementArguments, orderColumn: String)
        switch collection {
        case .recentlyImported:
            specification = ("1 = 1", [], "imported_at_ms")
        case .recentlyPlayed:
            specification = ("last_played_at_ms IS NOT NULL", [], "last_played_at_ms")
        case .downloaded:
            specification = ("download_state = 'available'", [], "imported_at_ms")
        case .folder(let folderID):
            specification = ("folder_id = ?", [identifier(folderID)], "imported_at_ms")
        }

        let sql: String
        var arguments = specification.arguments
        if let cursor {
            sql = """
                SELECT * FROM audio_items
                WHERE \(specification.whereClause)
                    AND (\(specification.orderColumn) < ?
                        OR (\(specification.orderColumn) = ? AND id < ?))
                ORDER BY \(specification.orderColumn) DESC, id DESC
                LIMIT ?
                """
            arguments += [
                cursor.sortValueMilliseconds,
                cursor.sortValueMilliseconds,
                identifier(cursor.itemID),
                limit,
            ]
        } else {
            sql = """
                SELECT * FROM audio_items
                WHERE \(specification.whereClause)
                ORDER BY \(specification.orderColumn) DESC, id DESC
                LIMIT ?
                """
            arguments += [limit]
        }
        return try Row.fetchAll(database, sql: sql, arguments: arguments).map(item(from:))
    }

    static func collectionSortValue(for item: AudioItem, in collection: LibraryCollection) -> Int64
    {
        switch collection {
        case .recentlyPlayed:
            milliseconds(item.lastPlayedAt ?? .distantPast)
        case .recentlyImported, .downloaded, .folder:
            milliseconds(item.importedAt)
        }
    }
}
