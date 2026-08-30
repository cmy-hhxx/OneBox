import Foundation
import GRDB
import GRDBSQLite

enum DatabaseSchema {
    static func initialize(_ writer: DatabaseQueue) throws {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("createPodPinLibrary") { database in
            try database.execute(
                sql: """
                    CREATE TABLE library_folders (
                        id TEXT NOT NULL PRIMARY KEY,
                        parent_id TEXT REFERENCES library_folders(id) ON DELETE RESTRICT,
                        parent_key TEXT NOT NULL,
                        name TEXT NOT NULL CHECK(length(trim(name)) > 0),
                        normalized_name TEXT NOT NULL CHECK(length(normalized_name) > 0),
                        system_kind TEXT NOT NULL CHECK(system_kind IN ('user', 'inbox')),
                        created_at_ms INTEGER NOT NULL,
                        CHECK(
                            (parent_id IS NULL AND parent_key = '')
                            OR (parent_id IS NOT NULL AND parent_key = parent_id)
                        )
                    ) STRICT;
                    """)
            try database.execute(
                sql: """
                    CREATE UNIQUE INDEX library_folders_parent_normalized_name
                    ON library_folders(parent_key, normalized_name);
                    """)
            try database.execute(
                sql: """
                    CREATE INDEX library_folders_parent_id
                    ON library_folders(parent_id);
                    """)

            try database.execute(
                sql: """
                    CREATE TABLE audio_items (
                        id TEXT NOT NULL PRIMARY KEY,
                        platform TEXT NOT NULL CHECK(length(trim(platform)) > 0),
                        content_id TEXT NOT NULL CHECK(length(trim(content_id)) > 0),
                        source_url TEXT NOT NULL CHECK(length(trim(source_url)) > 0),
                        title TEXT NOT NULL CHECK(length(trim(title)) > 0),
                        author TEXT,
                        artwork_relative_path TEXT,
                        duration_ms INTEGER CHECK(duration_ms IS NULL OR duration_ms >= 0),
                        folder_id TEXT NOT NULL REFERENCES library_folders(id) ON DELETE RESTRICT,
                        storage_kind TEXT NOT NULL CHECK(storage_kind IN ('online', 'offline')),
                        download_state TEXT NOT NULL CHECK(
                            download_state IN ('not_requested', 'downloading', 'available', 'failed')
                        ),
                        local_media_relative_path TEXT,
                        playback_position_ms INTEGER NOT NULL DEFAULT 0 CHECK(playback_position_ms >= 0),
                        last_played_at_ms INTEGER,
                        imported_at_ms INTEGER NOT NULL,
                        updated_at_ms INTEGER NOT NULL,
                        CHECK(
                            (storage_kind = 'online'
                                AND download_state = 'not_requested'
                                AND local_media_relative_path IS NULL)
                            OR
                            (storage_kind = 'offline'
                                AND download_state IN ('downloading', 'available', 'failed')
                                AND (
                                    (download_state = 'available' AND local_media_relative_path IS NOT NULL)
                                    OR (download_state != 'available' AND local_media_relative_path IS NULL)
                                ))
                        ),
                        UNIQUE(platform, content_id)
                    ) STRICT;
                    """)
            try database.execute(
                sql: """
                    CREATE INDEX audio_items_folder_imported_at
                    ON audio_items(folder_id, imported_at_ms DESC, id DESC);
                    """)

            try database.execute(
                sql: """
                    CREATE TABLE player_state (
                        singleton INTEGER NOT NULL PRIMARY KEY CHECK(singleton = 1),
                        current_item_id TEXT REFERENCES audio_items(id) ON DELETE SET NULL,
                        updated_at_ms INTEGER NOT NULL
                    ) STRICT;
                    """)

            try database.execute(
                sql: """
                    INSERT INTO library_folders (
                        id, parent_id, parent_key, name, normalized_name, system_kind, created_at_ms
                    ) VALUES (?, NULL, '', ?, ?, 'inbox', ?)
                    """,
                arguments: [
                    LibraryFolder.inboxID.uuidString.lowercased(),
                    LibraryFolder.inbox.name,
                    "inbox",
                    0,
                ]
            )
            try database.execute(
                sql:
                    "INSERT INTO player_state (singleton, current_item_id, updated_at_ms) VALUES (1, NULL, 0)"
            )
        }
        migrator.registerMigration("requireAudioItemFolder") { database in
            let columns = try Row.fetchAll(database, sql: "PRAGMA table_info(audio_items)")
            let folderIDIsRequired = columns.contains { row in
                let name: String = row["name"]
                let isRequired: Int = row["notnull"]
                return name == "folder_id" && isRequired != 0
            }
            guard !folderIDIsRequired else { return }

            // The first released schema permitted unfiled audio. Make the
            // inbox available before copying, then rebuild the table because
            // SQLite cannot add a NOT NULL constraint in place. GRDB runs a
            // migration in a transaction, so a failure leaves both the old
            // rows and their media paths untouched.
            try database.execute(
                sql: """
                    INSERT OR IGNORE INTO library_folders (
                        id, parent_id, parent_key, name, normalized_name, system_kind, created_at_ms
                    ) VALUES (?, NULL, '', ?, ?, 'inbox', 0)
                    """,
                arguments: [
                    LibraryFolder.inboxID.uuidString.lowercased(),
                    LibraryFolder.inbox.name,
                    "inbox",
                ]
            )
            try database.execute(
                sql: "UPDATE audio_items SET folder_id = ? WHERE folder_id IS NULL",
                arguments: [LibraryFolder.inboxID.uuidString.lowercased()]
            )

            try database.execute(
                sql: """
                    CREATE TABLE audio_items_rebuilt (
                        id TEXT NOT NULL PRIMARY KEY,
                        platform TEXT NOT NULL CHECK(length(trim(platform)) > 0),
                        content_id TEXT NOT NULL CHECK(length(trim(content_id)) > 0),
                        source_url TEXT NOT NULL CHECK(length(trim(source_url)) > 0),
                        title TEXT NOT NULL CHECK(length(trim(title)) > 0),
                        author TEXT,
                        artwork_relative_path TEXT,
                        duration_ms INTEGER CHECK(duration_ms IS NULL OR duration_ms >= 0),
                        folder_id TEXT NOT NULL REFERENCES library_folders(id) ON DELETE RESTRICT,
                        storage_kind TEXT NOT NULL CHECK(storage_kind IN ('online', 'offline')),
                        download_state TEXT NOT NULL CHECK(
                            download_state IN ('not_requested', 'downloading', 'available', 'failed')
                        ),
                        local_media_relative_path TEXT,
                        playback_position_ms INTEGER NOT NULL DEFAULT 0 CHECK(playback_position_ms >= 0),
                        last_played_at_ms INTEGER,
                        imported_at_ms INTEGER NOT NULL,
                        updated_at_ms INTEGER NOT NULL,
                        CHECK(
                            (storage_kind = 'online'
                                AND download_state = 'not_requested'
                                AND local_media_relative_path IS NULL)
                            OR
                            (storage_kind = 'offline'
                                AND download_state IN ('downloading', 'available', 'failed')
                                AND (
                                    (download_state = 'available' AND local_media_relative_path IS NOT NULL)
                                    OR (download_state != 'available' AND local_media_relative_path IS NULL)
                                ))
                        ),
                        UNIQUE(platform, content_id)
                    ) STRICT;
                    """)
            try database.execute(
                sql: """
                    INSERT INTO audio_items_rebuilt (
                        id, platform, content_id, source_url, title, author, artwork_relative_path,
                        duration_ms, folder_id, storage_kind, download_state, local_media_relative_path,
                        playback_position_ms, last_played_at_ms, imported_at_ms, updated_at_ms
                    )
                    SELECT
                        id, platform, content_id, source_url, title, author, artwork_relative_path,
                        duration_ms, folder_id, storage_kind, download_state, local_media_relative_path,
                        playback_position_ms, last_played_at_ms, imported_at_ms, updated_at_ms
                    FROM audio_items;
                    """)

            // Rebuild player_state as well: it owns the foreign key to the
            // table being replaced, and copying it keeps the current playback
            // item intact without disabling foreign-key enforcement.
            try database.execute(
                sql: """
                    CREATE TABLE player_state_rebuilt (
                        singleton INTEGER NOT NULL PRIMARY KEY CHECK(singleton = 1),
                        current_item_id TEXT,
                        updated_at_ms INTEGER NOT NULL
                    ) STRICT;
                    """)
            try database.execute(
                sql: """
                    INSERT INTO player_state_rebuilt (singleton, current_item_id, updated_at_ms)
                    SELECT singleton, current_item_id, updated_at_ms FROM player_state;
                    """)
            try database.execute(sql: "DROP TABLE player_state")
            try database.execute(sql: "DROP INDEX audio_items_folder_imported_at")
            try database.execute(sql: "DROP TABLE audio_items")
            try database.execute(sql: "ALTER TABLE audio_items_rebuilt RENAME TO audio_items")
            try database.execute(
                sql: """
                    CREATE INDEX audio_items_folder_imported_at
                    ON audio_items(folder_id, imported_at_ms DESC, id DESC);
                    """)
            try database.execute(
                sql: """
                    CREATE TABLE player_state (
                        singleton INTEGER NOT NULL PRIMARY KEY CHECK(singleton = 1),
                        current_item_id TEXT REFERENCES audio_items(id) ON DELETE SET NULL,
                        updated_at_ms INTEGER NOT NULL
                    ) STRICT;
                    """)
            try database.execute(
                sql: """
                    INSERT INTO player_state (singleton, current_item_id, updated_at_ms)
                    SELECT singleton, current_item_id, updated_at_ms FROM player_state_rebuilt;
                    """)
            try database.execute(
                sql:
                    "INSERT OR IGNORE INTO player_state (singleton, current_item_id, updated_at_ms) VALUES (1, NULL, 0)"
            )
            try database.execute(sql: "DROP TABLE player_state_rebuilt")
        }
        migrator.registerMigration("addStableItemPageIndex") { database in
            try database.execute(sql: "DROP INDEX IF EXISTS audio_items_folder_imported_at")
            try database.execute(
                sql: """
                    CREATE INDEX audio_items_folder_imported_at
                    ON audio_items(folder_id, imported_at_ms DESC, id DESC);
                    """)
        }
        migrator.registerMigration("addCollectionsAndPlaybackQueue") { database in
            try database.execute(
                sql: """
                    CREATE INDEX audio_items_last_played_at
                    ON audio_items(last_played_at_ms DESC, id DESC)
                    WHERE last_played_at_ms IS NOT NULL;
                    """)
            try database.execute(
                sql: """
                    CREATE INDEX audio_items_downloaded_imported_at
                    ON audio_items(imported_at_ms DESC, id DESC)
                    WHERE download_state = 'available';
                    """)
            try database.execute(
                sql: """
                    CREATE TABLE playback_queue (
                        item_id TEXT NOT NULL PRIMARY KEY REFERENCES audio_items(id) ON DELETE CASCADE,
                        position INTEGER NOT NULL CHECK(position >= 0),
                        enqueued_at_ms INTEGER NOT NULL
                    ) STRICT;
                    """)
            try database.execute(
                sql: """
                    CREATE INDEX playback_queue_position
                    ON playback_queue(position ASC);
                    """)
        }
        migrator.registerMigration("addListeningHistory") { database in
            try database.execute(
                sql: """
                    ALTER TABLE audio_items
                    ADD COLUMN listening_history_json TEXT NOT NULL DEFAULT '{"intervals":[]}';
                    """)
        }
        try migrator.migrate(writer)
    }
}
