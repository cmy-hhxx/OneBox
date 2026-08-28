import Foundation
import GRDB
import GRDBSQLite

enum DatabaseSchema {
    static let version = 2
    static let applicationID = 0x4D53_5052

    static func initialize(
        _ writer: any DatabaseWriter,
        cancellationToken: DatabaseCancellationToken? = nil
    ) throws {
        try writer.write { database in
            let version = try currentVersion(in: database)
            let storedApplicationID = try currentApplicationID(in: database)

            if version == 0, storedApplicationID == 0, try isEmpty(database) {
                try createCurrentSchema(in: database)
                try database.execute(sql: "PRAGMA application_id = \(self.applicationID)")
                try database.execute(sql: "PRAGMA user_version = \(self.version)")
            } else {
                try validate(database, cancellationToken: cancellationToken)
            }
        }
    }

    static func validate(
        _ reader: any DatabaseReader,
        cancellationToken: DatabaseCancellationToken? = nil
    ) throws {
        try reader.read { database in
            try validate(database, cancellationToken: cancellationToken)
        }
    }

    static func validate(
        _ database: Database,
        cancellationToken: DatabaseCancellationToken? = nil
    ) throws {
        try withCancellationProgressHandler(
            in: database,
            cancellationToken: cancellationToken
        ) {
            let applicationID = try currentApplicationID(in: database)
            guard applicationID == self.applicationID else {
                throw MarketDatabaseError.unrecognizedDatabase(applicationID)
            }

            let version = try currentVersion(in: database)
            guard version == self.version else {
                throw MarketDatabaseError.unsupportedSchemaVersion(version)
            }

            try validateCurrentStructure(in: database)
            try cancellationToken?.checkCancellation()

            guard try String.fetchOne(database, sql: "PRAGMA quick_check") == "ok" else {
                throw MarketDatabaseError.integrityCheckFailed
            }
            try cancellationToken?.checkCancellation()
            guard try Row.fetchAll(database, sql: "PRAGMA foreign_key_check").isEmpty else {
                throw MarketDatabaseError.integrityCheckFailed
            }
        }
    }

    static func withCancellationProgressHandler<T>(
        in database: Database,
        cancellationToken: DatabaseCancellationToken?,
        _ operation: () throws -> T
    ) throws -> T {
        guard let cancellationToken else {
            return try operation()
        }
        try cancellationToken.checkCancellation()
        let context = Unmanaged.passUnretained(cancellationToken).toOpaque()
        sqlite3_progress_handler(
            database.sqliteConnection,
            1_000,
            { context in
                guard let context else { return 0 }
                let token = Unmanaged<DatabaseCancellationToken>
                    .fromOpaque(context)
                    .takeUnretainedValue()
                return token.isCancelled ? 1 : 0
            },
            context
        )
        defer {
            sqlite3_progress_handler(database.sqliteConnection, 0, nil, nil)
        }

        do {
            let result = try operation()
            try cancellationToken.checkCancellation()
            return result
        } catch {
            if cancellationToken.isCancelled {
                throw CancellationError()
            }
            throw error
        }
    }

    private static func currentVersion(in database: Database) throws -> Int {
        try Int.fetchOne(database, sql: "PRAGMA user_version") ?? 0
    }

    private static func currentApplicationID(in database: Database) throws -> Int {
        try Int.fetchOne(database, sql: "PRAGMA application_id") ?? 0
    }

    private static func isEmpty(_ database: Database) throws -> Bool {
        try String.fetchOne(
            database,
            sql: "SELECT name FROM sqlite_schema WHERE type = 'table' LIMIT 1"
        ) == nil
    }

    private static func validateCurrentStructure(in database: Database) throws {
        try validateSchemaObjects(in: database)
        let tableRows = try Row.fetchAll(database, sql: "PRAGMA table_list")
        for contract in tableContracts {
            guard
                let tableRow = tableRows.first(where: { row in
                    let schema: String = row["schema"]
                    let name: String = row["name"]
                    return schema == "main" && name == contract.name
                })
            else {
                throw MarketDatabaseError.invalidSchema("missing table: \(contract.name)")
            }

            let type: String = tableRow["type"]
            let columnCount: Int = tableRow["ncol"]
            let withoutRowID: Int = tableRow["wr"]
            let strict: Int = tableRow["strict"]
            guard type == "table",
                columnCount == contract.columns.count,
                withoutRowID == 1,
                strict == 1
            else {
                throw MarketDatabaseError.invalidSchema(
                    "invalid table flags: \(contract.name)"
                )
            }

            try validateColumns(contract, in: database)
            try validateForeignKeys(contract, in: database)
            try validateUniqueColumns(contract, in: database)
            try validateChecks(contract, in: database)
        }
    }

    private static func validateSchemaObjects(in database: Database) throws {
        let expectedTables = Set(tableContracts.map(\.name))
        let rows = try Row.fetchAll(
            database,
            sql: "SELECT type, name, tbl_name, sql FROM sqlite_schema"
        )
        for row in rows {
            let type: String = row["type"]
            let name: String = row["name"]
            let tableName: String = row["tbl_name"]
            let sql: String? = row["sql"]

            if expectedTables.contains(name) {
                guard type == "table", tableName == name, sql != nil else {
                    throw MarketDatabaseError.invalidSchema(
                        "invalid schema object: \(name)"
                    )
                }
                continue
            }

            if name == "sqlite_autoindex_watchlist_2" {
                guard type == "index", tableName == "watchlist", sql == nil else {
                    throw MarketDatabaseError.invalidSchema(
                        "invalid schema object: \(name)"
                    )
                }
                continue
            }

            if sqliteInternalTableNames.contains(name) {
                guard type == "table", tableName == name else {
                    throw MarketDatabaseError.invalidSchema(
                        "invalid SQLite schema object: \(name)"
                    )
                }
                continue
            }

            throw MarketDatabaseError.invalidSchema(
                "unexpected schema object: \(type) \(name)"
            )
        }
    }

    private static func validateColumns(
        _ contract: TableContract,
        in database: Database
    ) throws {
        let rows = try Row.fetchAll(
            database,
            sql: "PRAGMA table_xinfo(\(quotedIdentifier(contract.name)))"
        )
        guard rows.count == contract.columns.count else {
            throw MarketDatabaseError.invalidSchema(
                "invalid columns: \(contract.name)"
            )
        }

        for (row, expected) in zip(rows, contract.columns) {
            let name: String = row["name"]
            let type: String = row["type"]
            let notNull: Int = row["notnull"]
            let defaultValue: String? = row["dflt_value"]
            let primaryKeyPosition: Int = row["pk"]
            let hidden: Int = row["hidden"]
            guard name == expected.name,
                type.uppercased() == expected.type,
                notNull == (expected.isNotNull ? 1 : 0),
                defaultValue == nil,
                primaryKeyPosition == expected.primaryKeyPosition,
                hidden == 0
            else {
                throw MarketDatabaseError.invalidSchema(
                    "invalid column: \(contract.name).\(expected.name)"
                )
            }
        }
    }

    private static func validateForeignKeys(
        _ contract: TableContract,
        in database: Database
    ) throws {
        let rows = try Row.fetchAll(
            database,
            sql: "PRAGMA foreign_key_list(\(quotedIdentifier(contract.name)))"
        )
        guard rows.count == contract.foreignKeys.count else {
            throw MarketDatabaseError.invalidSchema(
                "invalid foreign keys: \(contract.name)"
            )
        }

        for expected in contract.foreignKeys {
            let matches = rows.contains { row in
                let destinationTable: String = row["table"]
                let sourceColumn: String = row["from"]
                let destinationColumn: String = row["to"]
                let onUpdate: String = row["on_update"]
                let onDelete: String = row["on_delete"]
                let match: String = row["match"]
                return destinationTable == expected.destinationTable
                    && sourceColumn == expected.sourceColumn
                    && destinationColumn == expected.destinationColumn
                    && onUpdate.uppercased() == "NO ACTION"
                    && onDelete.uppercased() == expected.onDelete
                    && match.uppercased() == "NONE"
            }
            guard matches else {
                throw MarketDatabaseError.invalidSchema(
                    "invalid foreign key: \(contract.name).\(expected.sourceColumn)"
                )
            }
        }
    }

    private static func validateUniqueColumns(
        _ contract: TableContract,
        in database: Database
    ) throws {
        guard !contract.uniqueColumns.isEmpty else { return }
        let indexRows = try Row.fetchAll(
            database,
            sql: "PRAGMA index_list(\(quotedIdentifier(contract.name)))"
        )
        var uniqueColumnSets = Set<[String]>()
        for row in indexRows {
            let isUnique: Int = row["unique"]
            let isPartial: Int = row["partial"]
            guard isUnique == 1, isPartial == 0 else { continue }
            let indexName: String = row["name"]
            let columnRows = try Row.fetchAll(
                database,
                sql: "PRAGMA index_info(\(quotedIdentifier(indexName)))"
            )
            let columns = columnRows.sorted { lhs, rhs in
                let leftSequence: Int = lhs["seqno"]
                let rightSequence: Int = rhs["seqno"]
                return leftSequence < rightSequence
            }.map { row -> String in
                row["name"]
            }
            uniqueColumnSets.insert(columns)
        }

        for columns in contract.uniqueColumns where !uniqueColumnSets.contains(columns) {
            throw MarketDatabaseError.invalidSchema(
                "missing unique constraint: \(contract.name).\(columns.joined(separator: ","))"
            )
        }
    }

    private static func validateChecks(
        _ contract: TableContract,
        in database: Database
    ) throws {
        guard
            let sql = try String.fetchOne(
                database,
                sql: "SELECT sql FROM sqlite_schema WHERE type = 'table' AND name = ?",
                arguments: [contract.name]
            )
        else {
            throw MarketDatabaseError.invalidSchema("missing SQL: \(contract.name)")
        }
        let normalizedSQL = normalized(sql)
        for check in contract.checks where !normalizedSQL.contains(normalized(check)) {
            throw MarketDatabaseError.invalidSchema(
                "missing constraint: \(contract.name)"
            )
        }
    }

    private static func quotedIdentifier(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    private static func normalized(_ sql: String) -> String {
        sql.components(separatedBy: .whitespacesAndNewlines).joined().lowercased()
    }

    private static let sqliteInternalTableNames: Set<String> = [
        "sqlite_sequence",
        "sqlite_stat1",
        "sqlite_stat2",
        "sqlite_stat3",
        "sqlite_stat4",
    ]

    private static let tableContracts = [
        TableContract(
            name: "watchlist",
            columns: [
                ColumnContract("instrument_id", "TEXT", isNotNull: true, primaryKeyPosition: 1),
                ColumnContract("namespace", "TEXT", isNotNull: true),
                ColumnContract("symbol", "TEXT", isNotNull: true),
                ColumnContract("name", "TEXT", isNotNull: true),
                ColumnContract("position", "INTEGER", isNotNull: true),
            ],
            uniqueColumns: [["position"]],
            checks: [
                "CHECK(namespace IN ('sse', 'szse', 'bse', 'hk', 'us'))",
                """
                CHECK(
                    length(name) BETWEEN 1 AND 128
                    AND name = trim(name)
                    AND instr(name, ':') = 0
                )
                """,
                "CHECK(position >= 0)",
                "CHECK(instrument_id = namespace || ':' || symbol)",
                """
                CHECK(
                    (namespace IN ('sse', 'szse', 'bse')
                        AND length(symbol) = 6
                        AND symbol NOT GLOB '*[^0-9]*')
                    OR (namespace = 'hk'
                        AND length(symbol) = 5
                        AND symbol NOT GLOB '*[^0-9]*')
                    OR (namespace = 'us'
                        AND length(symbol) BETWEEN 1 AND 16
                        AND symbol NOT GLOB '*[^A-Z0-9.-]*')
                )
                """,
            ]
        ),
        TableContract(
            name: "alert_settings",
            columns: [
                ColumnContract("singleton", "INTEGER", isNotNull: true, primaryKeyPosition: 1),
                ColumnContract("enabled", "INTEGER", isNotNull: true),
                ColumnContract("basis", "TEXT", isNotNull: true),
                ColumnContract("rising_percent", "REAL", isNotNull: true),
                ColumnContract("falling_percent", "REAL", isNotNull: true),
            ],
            checks: [
                "CHECK(singleton = 1)",
                "CHECK(enabled IN (0, 1))",
                "CHECK(basis IN ('percentage', 'target_price'))",
                "CHECK(rising_percent BETWEEN 0.5 AND 15.0)",
                "CHECK(falling_percent BETWEEN 0.5 AND 15.0)",
            ]
        ),
        TableContract(
            name: "price_alerts",
            columns: [
                ColumnContract("instrument_id", "TEXT", isNotNull: true, primaryKeyPosition: 1),
                ColumnContract("rising_price", "REAL"),
                ColumnContract("falling_price", "REAL"),
            ],
            foreignKeys: [
                ForeignKeyContract(
                    sourceColumn: "instrument_id",
                    destinationTable: "watchlist",
                    destinationColumn: "instrument_id",
                    onDelete: "CASCADE"
                )
            ],
            checks: [
                "CHECK(rising_price > 0)",
                "CHECK(falling_price > 0)",
                "CHECK(rising_price IS NOT NULL OR falling_price IS NOT NULL)",
            ]
        ),
        TableContract(
            name: "quote_cache",
            columns: [
                ColumnContract("instrument_id", "TEXT", isNotNull: true, primaryKeyPosition: 1),
                ColumnContract("session_date", "TEXT", isNotNull: true),
                ColumnContract("day_open", "REAL", isNotNull: true),
                ColumnContract("previous_close", "REAL", isNotNull: true),
                ColumnContract("last_price", "REAL", isNotNull: true),
                ColumnContract("quoted_at_ms", "INTEGER", isNotNull: true),
                ColumnContract("received_at_ms", "INTEGER", isNotNull: true),
                ColumnContract("source", "TEXT", isNotNull: true),
            ],
            foreignKeys: [
                ForeignKeyContract(
                    sourceColumn: "instrument_id",
                    destinationTable: "watchlist",
                    destinationColumn: "instrument_id",
                    onDelete: "CASCADE"
                )
            ],
            checks: [
                """
                CHECK(
                    session_date GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]'
                )
                """,
                "CHECK(day_open > 0)",
                "CHECK(previous_close > 0)",
                "CHECK(last_price > 0)",
                "CHECK(quoted_at_ms > 0)",
                "CHECK(received_at_ms > 0)",
                "CHECK(source IN ('tencent', 'east_money'))",
            ]
        ),
        TableContract(
            name: "minute_bars",
            columns: [
                ColumnContract("instrument_id", "TEXT", isNotNull: true, primaryKeyPosition: 1),
                ColumnContract("minute_at_ms", "INTEGER", isNotNull: true, primaryKeyPosition: 2),
                ColumnContract("open", "REAL", isNotNull: true),
                ColumnContract("close", "REAL", isNotNull: true),
                ColumnContract("high", "REAL", isNotNull: true),
                ColumnContract("low", "REAL", isNotNull: true),
            ],
            foreignKeys: [
                ForeignKeyContract(
                    sourceColumn: "instrument_id",
                    destinationTable: "quote_cache",
                    destinationColumn: "instrument_id",
                    onDelete: "CASCADE"
                )
            ],
            checks: [
                "CHECK(minute_at_ms > 0)",
                "CHECK(open > 0)",
                "CHECK(close > 0)",
                "CHECK(high >= open AND high >= close)",
                "CHECK(low <= open AND low <= close)",
                "CHECK(low <= high)",
            ]
        ),
    ]

    private struct TableContract: Sendable {
        let name: String
        let columns: [ColumnContract]
        var foreignKeys: [ForeignKeyContract] = []
        var uniqueColumns: [[String]] = []
        let checks: [String]
    }

    private struct ColumnContract: Sendable {
        let name: String
        let type: String
        let isNotNull: Bool
        let primaryKeyPosition: Int

        init(
            _ name: String,
            _ type: String,
            isNotNull: Bool = false,
            primaryKeyPosition: Int = 0
        ) {
            self.name = name
            self.type = type
            self.isNotNull = isNotNull
            self.primaryKeyPosition = primaryKeyPosition
        }
    }

    private struct ForeignKeyContract: Sendable {
        let sourceColumn: String
        let destinationTable: String
        let destinationColumn: String
        let onDelete: String
    }

    private static func createCurrentSchema(in database: Database) throws {
        try database.execute(
            sql: """
                CREATE TABLE watchlist (
                    instrument_id TEXT NOT NULL PRIMARY KEY,
                    namespace TEXT NOT NULL CHECK(namespace IN ('sse', 'szse', 'bse', 'hk', 'us')),
                    symbol TEXT NOT NULL,
                    name TEXT NOT NULL CHECK(
                        length(name) BETWEEN 1 AND 128
                        AND name = trim(name)
                        AND instr(name, ':') = 0
                    ),
                    position INTEGER NOT NULL UNIQUE CHECK(position >= 0),
                    CHECK(instrument_id = namespace || ':' || symbol),
                    CHECK(
                        (namespace IN ('sse', 'szse', 'bse')
                            AND length(symbol) = 6
                            AND symbol NOT GLOB '*[^0-9]*')
                        OR (namespace = 'hk'
                            AND length(symbol) = 5
                            AND symbol NOT GLOB '*[^0-9]*')
                        OR (namespace = 'us'
                            AND length(symbol) BETWEEN 1 AND 16
                            AND symbol NOT GLOB '*[^A-Z0-9.-]*')
                    )
                ) STRICT, WITHOUT ROWID;
                """)

        try database.execute(
            sql: """
                CREATE TABLE alert_settings (
                    singleton INTEGER NOT NULL PRIMARY KEY CHECK(singleton = 1),
                    enabled INTEGER NOT NULL CHECK(enabled IN (0, 1)),
                    basis TEXT NOT NULL CHECK(basis IN ('percentage', 'target_price')),
                    rising_percent REAL NOT NULL CHECK(rising_percent BETWEEN 0.5 AND 15.0),
                    falling_percent REAL NOT NULL CHECK(falling_percent BETWEEN 0.5 AND 15.0)
                ) STRICT, WITHOUT ROWID;
                """)

        try database.execute(
            sql: """
                CREATE TABLE price_alerts (
                    instrument_id TEXT NOT NULL PRIMARY KEY
                        REFERENCES watchlist(instrument_id) ON DELETE CASCADE,
                    rising_price REAL CHECK(rising_price > 0),
                    falling_price REAL CHECK(falling_price > 0),
                    CHECK(rising_price IS NOT NULL OR falling_price IS NOT NULL)
                ) STRICT, WITHOUT ROWID;
                """)

        try database.execute(
            sql: """
                CREATE TABLE quote_cache (
                    instrument_id TEXT NOT NULL PRIMARY KEY
                        REFERENCES watchlist(instrument_id) ON DELETE CASCADE,
                    session_date TEXT NOT NULL CHECK(
                        session_date GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]'
                    ),
                    day_open REAL NOT NULL CHECK(day_open > 0),
                    previous_close REAL NOT NULL CHECK(previous_close > 0),
                    last_price REAL NOT NULL CHECK(last_price > 0),
                    quoted_at_ms INTEGER NOT NULL CHECK(quoted_at_ms > 0),
                    received_at_ms INTEGER NOT NULL CHECK(received_at_ms > 0),
                    source TEXT NOT NULL CHECK(source IN ('tencent', 'east_money'))
                ) STRICT, WITHOUT ROWID;
                """)

        try database.execute(
            sql: """
                CREATE TABLE minute_bars (
                    instrument_id TEXT NOT NULL
                        REFERENCES quote_cache(instrument_id) ON DELETE CASCADE,
                    minute_at_ms INTEGER NOT NULL CHECK(minute_at_ms > 0),
                    open REAL NOT NULL CHECK(open > 0),
                    close REAL NOT NULL CHECK(close > 0),
                    high REAL NOT NULL CHECK(high >= open AND high >= close),
                    low REAL NOT NULL CHECK(low <= open AND low <= close),
                    CHECK(low <= high),
                    PRIMARY KEY(instrument_id, minute_at_ms)
                ) STRICT, WITHOUT ROWID;
                """)

        let defaults = Instrument.initialWatchlist
        for (position, instrument) in defaults.enumerated() {
            try database.execute(
                sql: """
                    INSERT INTO watchlist (instrument_id, namespace, symbol, name, position)
                    VALUES (?, ?, ?, ?, ?)
                    """,
                arguments: [
                    instrument.id.rawValue,
                    instrument.namespace.rawValue,
                    instrument.symbol,
                    instrument.name,
                    position,
                ]
            )
        }
        try database.execute(
            sql: """
                INSERT INTO alert_settings (
                    singleton, enabled, basis, rising_percent, falling_percent
                ) VALUES (1, 1, 'percentage', 3.0, 3.0)
                """
        )
    }
}
