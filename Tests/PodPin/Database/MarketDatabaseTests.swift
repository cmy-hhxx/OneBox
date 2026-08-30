import Foundation
import GRDB
import XCTest

@testable import PodPinTool

final class MarketDatabaseTests: XCTestCase {
    func testFreshDatabaseCreatesTheSystemInbox() async throws {
        let database = try MarketDatabase.inMemory()

        let inbox = try await database.inbox()
        let rootFolders = try await database.listFolders()

        XCTAssertEqual(inbox, .inbox)
        XCTAssertEqual(rootFolders, [.inbox])
    }

    func testFoldersEnforceSiblingNamesAndTreeRules() async throws {
        let database = try MarketDatabase.inMemory()
        let projects = try await database.createFolder(named: " Projects ")
        let archive = try await database.createFolder(named: "Archive")
        let nested = try await database.createFolder(named: "2026", parentID: projects.id)
        let inboxChild = try await database.createFolder(
            named: "待整理",
            parentID: LibraryFolder.inboxID
        )

        XCTAssertEqual(inboxChild.parentID, LibraryFolder.inboxID)

        do {
            _ = try await database.createFolder(named: "projects")
            XCTFail("Expected a case-insensitive duplicate-name error")
        } catch let error as MarketDatabaseError {
            XCTAssertEqual(error, .duplicateFolderName(parentID: nil, name: "projects"))
        }

        do {
            _ = try await database.moveFolder(projects.id, toParentID: nested.id)
            XCTFail("Expected a descendant move error")
        } catch let error as MarketDatabaseError {
            XCTAssertEqual(error, .cannotMoveFolderIntoDescendant(projects.id, nested.id))
        }

        let moved = try await database.moveFolder(nested.id, toParentID: archive.id)
        XCTAssertEqual(moved.parentID, archive.id)

        do {
            _ = try await database.renameFolder(LibraryFolder.inboxID, to: "Other")
            XCTFail("Expected the system inbox to be immutable")
        } catch let error as MarketDatabaseError {
            XCTAssertEqual(error, .cannotModifySystemFolder(LibraryFolder.inboxID))
        }

        do {
            _ = try await database.moveFolder(LibraryFolder.inboxID, toParentID: archive.id)
            XCTFail("Expected the system inbox to remain unmoved")
        } catch let error as MarketDatabaseError {
            XCTAssertEqual(error, .cannotModifySystemFolder(LibraryFolder.inboxID))
        }

        do {
            try await database.deleteFolder(LibraryFolder.inboxID)
            XCTFail("Expected the system inbox to remain undeletable")
        } catch let error as MarketDatabaseError {
            XCTAssertEqual(error, .cannotModifySystemFolder(LibraryFolder.inboxID))
        }
    }

    func testNonEmptyFolderCannotBeDeleted() async throws {
        let database = try MarketDatabase.inMemory()
        let folder = try await database.createFolder(named: "Saved")
        let item = makeItem(folderID: folder.id)
        _ = try await database.insertItem(item)

        do {
            try await database.deleteFolder(folder.id)
            XCTFail("Expected non-empty folder deletion to be rejected")
        } catch let error as MarketDatabaseError {
            XCTAssertEqual(error, .cannotDeleteNonEmptyFolder(folder.id))
        }

        try await database.deleteItem(item.id)
        try await database.deleteFolder(folder.id)
        let deletedFolder = try await database.folder(id: folder.id)
        XCTAssertNil(deletedFolder)
    }

    func testArchivePreservesIdentityProgressAndOfflineUpgrade() async throws {
        let database = try MarketDatabase.inMemory()
        let online = makeItem(duration: 20)

        let inserted = try await database.archive(
            ArchiveRequest(items: [online], destinationFolderID: LibraryFolder.inboxID)
        )
        guard case .inserted(let savedOnline) = try XCTUnwrap(inserted.itemResults.first) else {
            return XCTFail("The first archive should insert the new item")
        }
        _ = try await database.updatePlaybackPosition(for: savedOnline.id, position: 99)

        let downloaded = AudioItem(
            platform: .fixture,
            contentID: online.contentID,
            sourceURL: URL(string: "https://fixture.podpin.local/updated")!,
            title: "Updated title",
            author: "PodPin",
            duration: 20,
            storageKind: .offline,
            downloadState: .available,
            localMediaRelativePath: "Media/new/audio.m4a"
        )
        let upgraded = try await database.archive(
            ArchiveRequest(items: [downloaded], destinationFolderID: LibraryFolder.inboxID)
        ).items[0]

        XCTAssertEqual(upgraded.id, savedOnline.id)
        XCTAssertEqual(upgraded.storageKind, .offline)
        XCTAssertEqual(upgraded.downloadState, .available)
        XCTAssertEqual(upgraded.localMediaRelativePath, "Media/new/audio.m4a")
        XCTAssertEqual(upgraded.playbackPosition, 20)
        XCTAssertEqual(
            upgraded.importedAt.timeIntervalSince1970,
            savedOnline.importedAt.timeIntervalSince1970,
            accuracy: 0.001
        )

        let repeatedOnlineImport = makeItem(contentID: online.contentID, title: "Metadata refresh")
        let retainedOffline = try await database.refreshMetadata(repeatedOnlineImport)
        XCTAssertEqual(retainedOffline.storageKind, .offline)
        XCTAssertEqual(retainedOffline.localMediaRelativePath, "Media/new/audio.m4a")
        XCTAssertEqual(retainedOffline.title, "Metadata refresh")
    }

    func testArchiveBatchIsAtomicWhenAnyItemIsInvalid() async throws {
        let database = try MarketDatabase.inMemory()
        let valid = makeItem(contentID: "batch-valid")
        let invalid = makeItem(contentID: "batch-invalid", title: "   ")

        do {
            _ = try await database.archive(
                ArchiveRequest(items: [valid, invalid], destinationFolderID: LibraryFolder.inboxID)
            )
            XCTFail("Expected the complete batch to be rejected")
        } catch let error as MarketDatabaseError {
            XCTAssertEqual(error, .invalidTitle)
        }

        let savedItems = try await database.listAllItems()
        XCTAssertTrue(savedItems.isEmpty)
    }

    func testArchivingDuplicateMovesTheExistingItemAndKeepsProgressAndMedia() async throws {
        let database = try MarketDatabase.inMemory()
        let destination = try await database.createFolder(named: "目标文件夹")
        let original = try await database.insertItem(makeItem(contentID: "move-me", duration: 42))
        _ = try await database.updatePlaybackPosition(for: original.id, position: 12)
        _ = try await database.updateDownloadState(
            for: original.id,
            state: .available,
            localMediaRelativePath: "Media/\(original.id.uuidString)/audio.m4a",
            duration: 42
        )

        let incoming = makeItem(
            contentID: "move-me",
            title: "更新后的标题",
            duration: 42,
            folderID: destination.id
        )
        let archive = try await database.archive(
            ArchiveRequest(items: [incoming], destinationFolderID: destination.id)
        )
        guard case .moved(let moved, let fromFolderID) = try XCTUnwrap(archive.itemResults.first)
        else {
            return XCTFail("A duplicate archive into another folder must be reported as a move")
        }

        XCTAssertEqual(fromFolderID, LibraryFolder.inboxID)
        XCTAssertEqual(moved.id, original.id)
        XCTAssertEqual(moved.folderID, destination.id)
        XCTAssertEqual(moved.playbackPosition, 12)
        XCTAssertEqual(moved.localMediaRelativePath, "Media/\(original.id.uuidString)/audio.m4a")
        let inboxItems = try await database.listItems(in: LibraryFolder.inboxID)
        let destinationItems = try await database.listItems(in: destination.id)
        XCTAssertEqual(inboxItems, [])
        XCTAssertEqual(destinationItems.map(\.id), [original.id])

        let metadataOnly = makeItem(
            contentID: "move-me",
            title: "仅刷新元数据",
            duration: 42,
            folderID: LibraryFolder.inboxID
        )
        let refreshed = try await database.refreshMetadata(metadataOnly)
        XCTAssertEqual(refreshed.folderID, destination.id)
        XCTAssertEqual(refreshed.playbackPosition, 12)
        XCTAssertEqual(
            refreshed.localMediaRelativePath, "Media/\(original.id.uuidString)/audio.m4a")
    }

    func testItemPagesAreStableAndBounded() async throws {
        let database = try MarketDatabase.inMemory()
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let items = (0..<401).map { index in
            AudioItem(
                platform: .fixture,
                contentID: "page-\(index)",
                sourceURL: URL(string: "https://fixture.podpin.local/page-\(index)")!,
                title: "Page \(index)",
                author: "PodPin",
                duration: 1,
                importedAt: start.addingTimeInterval(TimeInterval(index))
            )
        }
        _ = try await database.archive(
            ArchiveRequest(items: items, destinationFolderID: LibraryFolder.inboxID)
        )

        let first = try await database.listItemPage(in: LibraryFolder.inboxID)
        let second = try await database.listItemPage(
            in: LibraryFolder.inboxID,
            after: try XCTUnwrap(first.nextCursor)
        )
        let third = try await database.listItemPage(
            in: LibraryFolder.inboxID,
            after: try XCTUnwrap(second.nextCursor)
        )

        XCTAssertEqual(first.items.count, 200)
        XCTAssertEqual(second.items.count, 200)
        XCTAssertEqual(third.items.count, 1)
        XCTAssertNil(third.nextCursor)
        XCTAssertEqual(
            Set(first.items.map(\.id) + second.items.map(\.id) + third.items.map(\.id)).count,
            401
        )
    }

    func testFirstPageAtTenThousandItemsStaysWithinTheInteractiveBudget() async throws {
        let database = try MarketDatabase.inMemory()
        let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)
        let fixture = (0..<10_000).map { index in
            AudioItem(
                platform: .fixture,
                contentID: "scale-\(index)",
                sourceURL: URL(string: "https://fixture.podpin.local/scale-\(index)")!,
                title: "Scale \(index)",
                duration: 1,
                importedAt: referenceDate.addingTimeInterval(TimeInterval(index))
            )
        }
        _ = try await database.archive(
            ArchiveRequest(items: fixture, destinationFolderID: LibraryFolder.inboxID)
        )

        let clock = ContinuousClock()
        let start = clock.now
        let page = try await database.listItemPage(in: LibraryFolder.inboxID)
        let elapsed = start.duration(to: clock.now)

        XCTAssertEqual(page.items.count, 200)
        XCTAssertNotNil(page.nextCursor)
        XCTAssertLessThan(
            elapsed, .seconds(1), "The first visible page must not scan all 10,000 rows.")
    }

    func testXiaoyuzhouPlatformRoundTripsWithoutSchemaMigration() async throws {
        let database = try MarketDatabase.inMemory()
        var item = makeItem(contentID: "6a75424b000a55a9bb042560")
        item.platform = .xiaoyuzhou
        item.sourceURL = URL(
            string: "https://www.xiaoyuzhoufm.com/episode/6a75424b000a55a9bb042560")!

        let saved = try await database.archive(
            ArchiveRequest(items: [item], destinationFolderID: LibraryFolder.inboxID)
        ).items[0]
        let restored = try await database.item(id: saved.id)

        XCTAssertEqual(restored?.platform, .xiaoyuzhou)
        XCTAssertEqual(restored?.contentID, "6a75424b000a55a9bb042560")
    }

    func testFiresidePlatformRoundTripsWithoutSchemaMigration() async throws {
        let database = try MarketDatabase.inMemory()
        var item = makeItem(contentID: "sv101.fireside.fm/260")
        item.platform = .fireside
        item.sourceURL = URL(string: "https://sv101.fireside.fm/260")!

        let saved = try await database.archive(
            ArchiveRequest(items: [item], destinationFolderID: LibraryFolder.inboxID)
        ).items[0]
        let restored = try await database.item(id: saved.id)

        XCTAssertEqual(restored?.platform, .fireside)
        XCTAssertEqual(restored?.contentID, "sv101.fireside.fm/260")
    }

    func testPlaybackStateClampsPositionAndSurvivesReopen() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PodPinDatabaseTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let databaseURL = directory.appendingPathComponent("podpin.sqlite")
        let firstDatabase = try MarketDatabase.open(at: databaseURL)
        let item = try await firstDatabase.insertItem(makeItem(duration: 30))

        let positioned = try await firstDatabase.updatePlaybackPosition(for: item.id, position: -5)
        XCTAssertEqual(positioned.playbackPosition, 0)
        _ = try await firstDatabase.updatePlaybackPosition(for: item.id, position: 45)
        try await firstDatabase.setCurrentPlaybackItem(item.id)

        let reopenedDatabase = try MarketDatabase.open(at: databaseURL)
        let restored = try await reopenedDatabase.currentPlaybackItem()

        XCTAssertEqual(restored?.id, item.id)
        XCTAssertEqual(restored?.playbackPosition, 30)
    }

    func testListeningHistoryPersistsWithPlaybackPosition() async throws {
        let database = try MarketDatabase.inMemory()
        let item = try await database.insertItem(makeItem(duration: 100))
        let history = ListeningHistory(intervals: [
            ListenedInterval(start: 0, end: 12),
            ListenedInterval(start: 40, end: 52),
        ])

        _ = try await database.updatePlaybackPosition(
            for: item.id,
            position: 52,
            listeningHistory: history
        )
        let restored = try await database.item(id: item.id)

        XCTAssertEqual(restored?.playbackPosition, 52)
        XCTAssertEqual(restored?.listeningHistory, history)
    }

    func testLegacyUnfiledItemsMigrateIntoInboxWithoutChangingMediaOrPlaybackState() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "PodPinLegacyMigrationTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let databaseURL = directory.appendingPathComponent("podpin.sqlite")
        let itemID = UUID()
        try writeLegacyDatabase(at: databaseURL, unfiledItemID: itemID)

        let database = try MarketDatabase.open(at: databaseURL)
        let restoredItem = try await database.item(id: itemID)
        let restored = try XCTUnwrap(restoredItem)
        let current = try await database.currentPlaybackItem()
        let inbox = try await database.inbox()

        XCTAssertEqual(restored.folderID, LibraryFolder.inboxID)
        XCTAssertEqual(restored.storageKind, .offline)
        XCTAssertEqual(restored.downloadState, .available)
        XCTAssertEqual(restored.artworkRelativePath, "Media/legacy/artwork.jpg")
        XCTAssertEqual(restored.localMediaRelativePath, "Media/legacy/audio.m4a")
        XCTAssertEqual(restored.duration, 91)
        XCTAssertEqual(restored.playbackPosition, 12.345, accuracy: 0.001)
        XCTAssertEqual(
            try XCTUnwrap(restored.lastPlayedAt).timeIntervalSince1970, 45.678, accuracy: 0.001)
        XCTAssertEqual(restored.importedAt.timeIntervalSince1970, 11.111, accuracy: 0.001)
        XCTAssertEqual(restored.updatedAt.timeIntervalSince1970, 22.222, accuracy: 0.001)
        XCTAssertEqual(current?.id, itemID)
        XCTAssertEqual(inbox.name, "Inbox")
        XCTAssertEqual(inbox.displayName, "收件箱")

        let inspector = try DatabaseQueue(path: databaseURL.path)
        let folderColumnIsRequired = try await inspector.read { database in
            let columns = try Row.fetchAll(database, sql: "PRAGMA table_info(audio_items)")
            guard
                let folderColumn = columns.first(where: { row in
                    let name: String = row["name"]
                    return name == "folder_id"
                })
            else {
                XCTFail("Expected folder_id column")
                return 0
            }
            let isRequired: Int = folderColumn["notnull"]
            return isRequired
        }
        XCTAssertEqual(folderColumnIsRequired, 1)
    }

    func testDownloadStateRequiresAValidatedRelativeMediaPath() async throws {
        let database = try MarketDatabase.inMemory()
        let item = try await database.insertItem(makeItem())

        let downloading = try await database.updateDownloadState(for: item.id, state: .downloading)
        XCTAssertEqual(downloading.storageKind, .offline)
        XCTAssertEqual(downloading.downloadState, .downloading)

        do {
            _ = try await database.updateDownloadState(
                for: item.id,
                state: .available,
                localMediaRelativePath: "../audio.m4a"
            )
            XCTFail("Expected a path traversal error")
        } catch let error as MarketDatabaseError {
            XCTAssertEqual(error, .invalidRelativePath)
        }

        let available = try await database.updateDownloadState(
            for: item.id,
            state: .available,
            localMediaRelativePath: "Media/\(item.id.uuidString)/audio.m4a",
            duration: 12.5
        )
        XCTAssertEqual(available.downloadState, .available)
        XCTAssertEqual(available.storageKind, .offline)
        XCTAssertEqual(available.duration, 12.5)
    }

    func testDownloadDurationReclampsSavedPlaybackPosition() async throws {
        let database = try MarketDatabase.inMemory()
        let item = try await database.insertItem(makeItem(duration: 30))
        _ = try await database.updatePlaybackPosition(for: item.id, position: 25)

        let downloaded = try await database.updateDownloadState(
            for: item.id,
            state: .available,
            localMediaRelativePath: "Media/\(item.id.uuidString)/audio.m4a",
            duration: 10
        )

        XCTAssertEqual(downloaded.duration, 10)
        XCTAssertEqual(downloaded.playbackPosition, 10)
    }

    func testArtworkUpdateDoesNotOverwriteOfflineDownloadState() async throws {
        let database = try MarketDatabase.inMemory()
        let item = try await database.insertItem(makeItem())
        _ = try await database.updateDownloadState(
            for: item.id,
            state: .available,
            localMediaRelativePath: "Media/\(item.id.uuidString)/audio.m4a",
            duration: 10
        )

        let updated = try await database.updateArtworkPath(
            for: item.id,
            relativePath: "Media/\(item.id.uuidString)/artwork"
        )

        XCTAssertEqual(updated.artworkRelativePath, "Media/\(item.id.uuidString)/artwork")
        XCTAssertEqual(updated.storageKind, .offline)
        XCTAssertEqual(updated.downloadState, .available)
        XCTAssertEqual(updated.localMediaRelativePath, "Media/\(item.id.uuidString)/audio.m4a")
    }

    func testInterruptedDownloadsBecomeRetryableOnStartup() async throws {
        let database = try MarketDatabase.inMemory()
        let item = try await database.insertItem(makeItem())
        _ = try await database.updateDownloadState(for: item.id, state: .downloading)

        let recovered = try await database.recoverInterruptedDownloads()
        let saved = try await database.item(id: item.id)

        XCTAssertEqual(recovered, [item.id])
        XCTAssertEqual(saved?.storageKind, .online)
        XCTAssertEqual(saved?.downloadState, .notRequested)
        XCTAssertNil(saved?.localMediaRelativePath)
    }

    func testSmartCollectionsFilterAndKeepTheirOwnStableOrder() async throws {
        let database = try MarketDatabase.inMemory()
        let importedFirst = try await database.insertItem(makeItem(contentID: "first"))
        try await Task.sleep(for: .milliseconds(2))
        let importedLast = try await database.insertItem(makeItem(contentID: "last"))
        _ = try await database.updatePlaybackPosition(for: importedFirst.id, position: 1)
        try await Task.sleep(for: .milliseconds(2))
        _ = try await database.updatePlaybackPosition(for: importedLast.id, position: 1)
        _ = try await database.updateDownloadState(
            for: importedFirst.id,
            state: .available,
            localMediaRelativePath: "Media/\(importedFirst.id.uuidString)/audio.m4a",
            duration: 8
        )

        let recentImports = try await database.listItemPage(in: .recentlyImported)
        let recentPlayback = try await database.listItemPage(in: .recentlyPlayed)
        let downloaded = try await database.listItemPage(in: .downloaded)

        XCTAssertEqual(recentImports.items.map(\.id), [importedLast.id, importedFirst.id])
        XCTAssertEqual(recentPlayback.items.map(\.id), [importedLast.id, importedFirst.id])
        XCTAssertEqual(downloaded.items.map(\.id), [importedFirst.id])
    }

    func testPersistentPlaybackQueueDeduplicatesReordersAndCascadesDeletedAudio() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PodPinQueueTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let databaseURL = directory.appendingPathComponent("podpin.sqlite")
        let firstDatabase = try MarketDatabase.open(at: databaseURL)
        let first = try await firstDatabase.insertItem(makeItem(contentID: "queue-first"))
        let second = try await firstDatabase.insertItem(makeItem(contentID: "queue-second"))

        _ = try await firstDatabase.enqueue(first.id, at: .last)
        _ = try await firstDatabase.enqueue(second.id, at: .last)
        _ = try await firstDatabase.enqueue(first.id, at: .last)
        let movedToTail = try await firstDatabase.playbackQueue()
        XCTAssertEqual(movedToTail.map(\.id), [second.id, first.id])

        _ = try await firstDatabase.enqueue(first.id, at: .next)
        let movedToHead = try await firstDatabase.playbackQueue()
        XCTAssertEqual(movedToHead.map(\.id), [first.id, second.id])
        _ = try await firstDatabase.moveQueueItem(first.id, to: 1)

        let reopenedDatabase = try MarketDatabase.open(at: databaseURL)
        let reopenedQueue = try await reopenedDatabase.playbackQueue()
        XCTAssertEqual(reopenedQueue.map(\.id), [second.id, first.id])

        let activatedItem = try await reopenedDatabase.activateQueueItem(second.id)
        XCTAssertEqual(activatedItem.id, second.id)
        let currentItem = try await reopenedDatabase.currentPlaybackItem()
        XCTAssertEqual(currentItem?.id, second.id)
        let queueAfterActivation = try await reopenedDatabase.playbackQueue()
        XCTAssertEqual(queueAfterActivation.map(\.id), [first.id])

        try await reopenedDatabase.deleteItem(first.id)
        let queueAfterDelete = try await reopenedDatabase.playbackQueue()
        XCTAssertTrue(queueAfterDelete.isEmpty)
    }

    private func makeItem(
        contentID: String = "welcome",
        title: String = "Welcome",
        duration: TimeInterval? = 8,
        folderID: UUID = LibraryFolder.inboxID
    ) -> AudioItem {
        AudioItem(
            platform: .fixture,
            contentID: contentID,
            sourceURL: URL(string: "https://fixture.podpin.local/\(contentID)")!,
            title: title,
            author: "PodPin",
            duration: duration,
            folderID: folderID
        )
    }

    private func writeLegacyDatabase(at url: URL, unfiledItemID: UUID) throws {
        let queue = try DatabaseQueue(path: url.path)
        try queue.write { database in
            try database.execute(
                sql: """
                    CREATE TABLE library_folders (
                        id TEXT NOT NULL PRIMARY KEY,
                        parent_id TEXT,
                        parent_key TEXT NOT NULL,
                        name TEXT NOT NULL,
                        normalized_name TEXT NOT NULL,
                        system_kind TEXT NOT NULL,
                        created_at_ms INTEGER NOT NULL
                    ) STRICT;
                    """)
            try database.execute(
                sql: """
                    CREATE TABLE audio_items (
                        id TEXT NOT NULL PRIMARY KEY,
                        platform TEXT NOT NULL,
                        content_id TEXT NOT NULL,
                        source_url TEXT NOT NULL,
                        title TEXT NOT NULL,
                        author TEXT,
                        artwork_relative_path TEXT,
                        duration_ms INTEGER,
                        folder_id TEXT,
                        storage_kind TEXT NOT NULL,
                        download_state TEXT NOT NULL,
                        local_media_relative_path TEXT,
                        playback_position_ms INTEGER NOT NULL,
                        last_played_at_ms INTEGER,
                        imported_at_ms INTEGER NOT NULL,
                        updated_at_ms INTEGER NOT NULL
                    ) STRICT;
                    """)
            try database.execute(
                sql: """
                    CREATE INDEX audio_items_folder_imported_at
                    ON audio_items(folder_id, imported_at_ms DESC);
                    """)
            try database.execute(
                sql: """
                    CREATE TABLE player_state (
                        singleton INTEGER NOT NULL PRIMARY KEY,
                        current_item_id TEXT,
                        updated_at_ms INTEGER NOT NULL
                    ) STRICT;
                    """)
            try database.execute(
                sql: "CREATE TABLE grdb_migrations (identifier TEXT NOT NULL PRIMARY KEY)")
            try database.execute(
                sql: """
                    INSERT INTO library_folders (
                        id, parent_id, parent_key, name, normalized_name, system_kind, created_at_ms
                    ) VALUES (?, NULL, '', 'Inbox', 'inbox', 'inbox', 0)
                    """,
                arguments: [LibraryFolder.inboxID.uuidString.lowercased()]
            )
            try database.execute(
                sql: """
                    INSERT INTO audio_items (
                        id, platform, content_id, source_url, title, author, artwork_relative_path,
                        duration_ms, folder_id, storage_kind, download_state, local_media_relative_path,
                        playback_position_ms, last_played_at_ms, imported_at_ms, updated_at_ms
                    ) VALUES (?, 'fixture', 'legacy-item', 'https://fixture.podpin.local/legacy',
                        'Legacy item', 'PodPin', 'Media/legacy/artwork.jpg', 91000, NULL,
                        'offline', 'available', 'Media/legacy/audio.m4a', 12345, 45678, 11111, 22222)
                    """,
                arguments: [unfiledItemID.uuidString.lowercased()]
            )
            try database.execute(
                sql:
                    "INSERT INTO player_state (singleton, current_item_id, updated_at_ms) VALUES (1, ?, 33333)",
                arguments: [unfiledItemID.uuidString.lowercased()]
            )
            try database.execute(
                sql: "INSERT INTO grdb_migrations (identifier) VALUES ('createPodPinLibrary')"
            )
        }
    }
}
