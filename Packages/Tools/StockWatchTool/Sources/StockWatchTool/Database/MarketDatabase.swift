import Foundation
import GRDB
import OSLog

actor MarketDatabase {
    static let defaultFileName = "marketsprite.sqlite"
    private static let signposter = OSSignposter(
        subsystem: "com.cmy.OneBox",
        category: "StockWatch"
    )

    private let databaseQueue: DatabaseQueue
    private let cancellationToken: DatabaseCancellationToken?
    nonisolated let databasePath: String

    private init(
        databaseQueue: DatabaseQueue,
        databasePath: String,
        initialize: Bool = true,
        cancellationToken: DatabaseCancellationToken? = nil
    ) throws {
        self.databaseQueue = databaseQueue
        self.cancellationToken = cancellationToken
        self.databasePath = databasePath
        if initialize {
            try DatabaseSchema.initialize(
                databaseQueue,
                cancellationToken: cancellationToken
            )
            try Self.normalizeWatchlistPositions(
                in: databaseQueue,
                cancellationToken: cancellationToken
            )
        } else {
            try DatabaseSchema.validate(
                databaseQueue,
                cancellationToken: cancellationToken
            )
        }
    }

    static func inMemory() throws -> MarketDatabase {
        try MarketDatabase(
            databaseQueue: DatabaseQueue(configuration: configuration()),
            databasePath: ":memory:"
        )
    }

    static func open(
        atPath path: String,
        cancellationToken: DatabaseCancellationToken? = nil
    ) throws -> MarketDatabase {
        try MarketDatabase(
            databaseQueue: DatabaseQueue(path: path, configuration: configuration()),
            databasePath: path,
            cancellationToken: cancellationToken
        )
    }

    static func openReadOnly(
        atPath path: String,
        cancellationToken: DatabaseCancellationToken? = nil
    ) throws -> MarketDatabase {
        try MarketDatabase(
            databaseQueue: DatabaseQueue(path: path, configuration: readOnlyConfiguration()),
            databasePath: path,
            initialize: false,
            cancellationToken: cancellationToken
        )
    }

    static func openInDirectory(
        _ folder: URL,
        fileName: String = defaultFileName,
        fileManager: FileManager = .default,
        cancellationToken: DatabaseCancellationToken? = nil
    ) throws -> MarketDatabase {
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        let canonicalURL = folder.appendingPathComponent(fileName, isDirectory: false)
        return try MarketDatabase(
            databaseQueue: DatabaseQueue(
                path: canonicalURL.path,
                configuration: configuration()
            ),
            databasePath: canonicalURL.path,
            cancellationToken: cancellationToken
        )
    }

    func loadWatchlist() throws -> [Instrument] {
        try databaseQueue.read { database in
            try DatabaseSchema.withCancellationProgressHandler(
                in: database,
                cancellationToken: cancellationToken
            ) {
                try Self.fetchWatchlist(from: database)
            }
        }
    }

    func replaceWatchlist(with instruments: [Instrument]) throws {
        let instrumentIDs = instruments.map(\.id)
        guard Set(instrumentIDs).count == instruments.count else {
            throw MarketDatabaseError.invalidWatchlist
        }

        try databaseQueue.write { database in
            let storedIDs = Set(
                try String.fetchAll(
                    database,
                    sql: "SELECT instrument_id FROM watchlist"
                ))
            let incomingIDs = Set(instrumentIDs.map(\.rawValue))

            for storedID in storedIDs.subtracting(incomingIDs) {
                try database.execute(
                    sql: "DELETE FROM watchlist WHERE instrument_id = ?",
                    arguments: [storedID]
                )
            }

            if !storedIDs.isEmpty {
                try database.execute(sql: "UPDATE watchlist SET position = position + 1000000")
            }

            for (position, instrument) in instruments.enumerated() {
                try database.execute(
                    sql: """
                        INSERT INTO watchlist (instrument_id, namespace, symbol, name, position)
                        VALUES (?, ?, ?, ?, ?)
                        ON CONFLICT(instrument_id) DO UPDATE SET
                            namespace = excluded.namespace,
                            symbol = excluded.symbol,
                            name = excluded.name,
                            position = excluded.position
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
        }
    }

    @discardableResult
    func saveQuote(_ snapshot: QuoteSnapshot, for instrument: Instrument) throws -> Bool {
        let interval = Self.signposter.beginInterval(
            "SynchronizeQuoteSnapshot",
            id: Self.signposter.makeSignpostID()
        )
        defer { Self.signposter.endInterval("SynchronizeQuoteSnapshot", interval) }

        let sessionDate = try Self.validatedSessionDate(
            for: snapshot,
            instrument: instrument
        )

        return try databaseQueue.write { database in
            let isObserved =
                try Bool.fetchOne(
                    database,
                    sql: "SELECT EXISTS(SELECT 1 FROM watchlist WHERE instrument_id = ?)",
                    arguments: [instrument.id.rawValue]
                ) ?? false
            guard isObserved else { return false }

            let storedSessionDate = try String.fetchOne(
                database,
                sql: "SELECT session_date FROM quote_cache WHERE instrument_id = ?",
                arguments: [instrument.id.rawValue]
            )
            if storedSessionDate != nil, storedSessionDate != sessionDate {
                try database.execute(
                    sql: "DELETE FROM quote_cache WHERE instrument_id = ?",
                    arguments: [instrument.id.rawValue]
                )
            }

            try database.execute(
                sql: """
                    INSERT INTO quote_cache (
                        instrument_id, session_date, day_open, previous_close, last_price,
                        quoted_at_ms, received_at_ms, source
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(instrument_id) DO UPDATE SET
                        session_date = excluded.session_date,
                        day_open = excluded.day_open,
                        previous_close = excluded.previous_close,
                        last_price = excluded.last_price,
                        quoted_at_ms = excluded.quoted_at_ms,
                        received_at_ms = excluded.received_at_ms,
                        source = excluded.source
                    """,
                arguments: [
                    instrument.id.rawValue,
                    sessionDate,
                    snapshot.dayOpen,
                    snapshot.previousClose,
                    snapshot.lastPrice,
                    Self.milliseconds(snapshot.marketTime),
                    Self.milliseconds(snapshot.receivedAt),
                    Self.sourceValue(snapshot.source),
                ]
            )

            let storedRows = try Row.fetchAll(
                database,
                sql: """
                    SELECT minute_at_ms, open, close, high, low
                    FROM minute_bars
                    WHERE instrument_id = ?
                    """,
                arguments: [instrument.id.rawValue]
            )
            let storedBars = Dictionary(
                uniqueKeysWithValues: storedRows.map { row in
                    let time: Int64 = row["minute_at_ms"]
                    return (
                        time,
                        MinuteBar(
                            time: Self.date(fromMilliseconds: time),
                            open: row["open"],
                            close: row["close"],
                            high: row["high"],
                            low: row["low"]
                        )
                    )
                })
            let incomingTimes = Set(snapshot.minuteBars.map { Self.milliseconds($0.time) })
            for storedTime in storedBars.keys where !incomingTimes.contains(storedTime) {
                try database.execute(
                    sql: "DELETE FROM minute_bars WHERE instrument_id = ? AND minute_at_ms = ?",
                    arguments: [instrument.id.rawValue, storedTime]
                )
            }
            for bar in snapshot.minuteBars {
                let minuteAt = Self.milliseconds(bar.time)
                guard storedBars[minuteAt] != bar else { continue }
                try database.execute(
                    sql: """
                        INSERT INTO minute_bars (
                            instrument_id, minute_at_ms, open, close, high, low
                        ) VALUES (?, ?, ?, ?, ?, ?)
                        ON CONFLICT(instrument_id, minute_at_ms) DO UPDATE SET
                            open = excluded.open,
                            close = excluded.close,
                            high = excluded.high,
                            low = excluded.low
                        """,
                    arguments: [
                        instrument.id.rawValue,
                        minuteAt,
                        bar.open,
                        bar.close,
                        bar.high,
                        bar.low,
                    ]
                )
            }
            return true
        }
    }

    func loadLatestQuotes(for instruments: [Instrument]) throws -> [InstrumentID: QuoteSnapshot] {
        try loadLatestQuotes(for: instruments, omittingInvalidRows: true)
    }

    func validateLatestQuotes(for instruments: [Instrument]) throws {
        _ = try loadLatestQuotes(for: instruments, omittingInvalidRows: false)
    }

    private func loadLatestQuotes(
        for instruments: [Instrument],
        omittingInvalidRows: Bool
    ) throws -> [InstrumentID: QuoteSnapshot] {
        guard !instruments.isEmpty else { return [:] }

        return try databaseQueue.read { database in
            try DatabaseSchema.withCancellationProgressHandler(
                in: database,
                cancellationToken: cancellationToken
            ) {
                var instrumentByRawID: [String: Instrument] = [:]
                for instrument in instruments {
                    instrumentByRawID[instrument.id.rawValue] = instrument
                }
                let placeholders = Array(repeating: "?", count: instrumentByRawID.count).joined(
                    separator: ", ")
                let arguments = StatementArguments(instrumentByRawID.keys.sorted())
                let sessions = try Row.fetchAll(
                    database,
                    sql: """
                        SELECT instrument_id, session_date, day_open, previous_close, last_price,
                               quoted_at_ms, received_at_ms, source
                        FROM quote_cache
                        WHERE instrument_id IN (\(placeholders))
                        """,
                    arguments: arguments
                )
                let rows = try Row.fetchAll(
                    database,
                    sql: """
                        SELECT instrument_id, minute_at_ms, open, close, high, low
                        FROM minute_bars
                        WHERE instrument_id IN (\(placeholders))
                        ORDER BY instrument_id, minute_at_ms
                        """,
                    arguments: arguments
                )
                var barsByInstrumentID: [InstrumentID: [MinuteBar]] = [:]
                for row in rows {
                    let rawID: String = row["instrument_id"]
                    guard let instrument = instrumentByRawID[rawID] else { continue }
                    let instrumentID = instrument.id
                    let time: Int64 = row["minute_at_ms"]
                    barsByInstrumentID[instrumentID, default: []].append(
                        MinuteBar(
                            time: Self.date(fromMilliseconds: time),
                            open: row["open"],
                            close: row["close"],
                            high: row["high"],
                            low: row["low"]
                        )
                    )
                }

                var snapshots: [InstrumentID: QuoteSnapshot] = [:]
                for session in sessions {
                    do {
                        let rawID: String = session["instrument_id"]
                        guard let instrument = instrumentByRawID[rawID] else { continue }
                        let instrumentID = instrument.id
                        let source: QuoteSource = try Self.quoteSource(from: session["source"])
                        let quotedAt: Int64 = session["quoted_at_ms"]
                        let receivedAt: Int64 = session["received_at_ms"]
                        let snapshot = QuoteSnapshot(
                            instrumentID: instrumentID,
                            minuteBars: barsByInstrumentID[instrumentID] ?? [],
                            dayOpen: session["day_open"],
                            previousClose: session["previous_close"],
                            lastPrice: session["last_price"],
                            marketTime: Self.date(fromMilliseconds: quotedAt),
                            receivedAt: Self.date(fromMilliseconds: receivedAt),
                            source: source
                        )
                        let storedSessionDate: String = session["session_date"]
                        try Self.validateStoredSessionDate(
                            storedSessionDate,
                            for: snapshot,
                            instrument: instrument
                        )
                        snapshots[instrumentID] = snapshot
                    } catch  where omittingInvalidRows {
                        continue
                    }
                }
                return snapshots
            }
        }
    }

    func quoteBarCount() throws -> Int {
        try databaseQueue.read { database in
            try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM minute_bars") ?? 0
        }
    }

    func clearQuotes() throws {
        try databaseQueue.write { database in
            try DatabaseSchema.withCancellationProgressHandler(
                in: database,
                cancellationToken: cancellationToken
            ) {
                try database.execute(sql: "DELETE FROM quote_cache")
            }
        }
    }

    func close() throws {
        try databaseQueue.close()
    }

    func loadAlertSettings() throws -> AlertSettingsSnapshot {
        try databaseQueue.read { database in
            try DatabaseSchema.withCancellationProgressHandler(
                in: database,
                cancellationToken: cancellationToken
            ) {
                guard
                    let row = try Row.fetchOne(
                        database,
                        sql: """
                            SELECT enabled, basis, rising_percent, falling_percent
                            FROM alert_settings WHERE singleton = 1
                            """
                    )
                else {
                    throw MarketDatabaseError.invalidAlertConfiguration
                }
                let basisValue: String = row["basis"]
                let basis = try Self.alertBasis(from: basisValue)
                let configuration = AlertConfiguration(
                    isEnabled: row["enabled"],
                    basis: basis,
                    risingThreshold: row["rising_percent"],
                    fallingThreshold: row["falling_percent"]
                )
                let rows = try Row.fetchAll(
                    database,
                    sql: "SELECT instrument_id, rising_price, falling_price FROM price_alerts"
                )
                let targets = try rows.reduce(into: [InstrumentID: PriceAlertTargets]()) {
                    result, row in
                    let storedID: String = row["instrument_id"]
                    let id = try InstrumentID(validatingRawValue: storedID)
                    let target = PriceAlertTargets(
                        risingPrice: row["rising_price"],
                        fallingPrice: row["falling_price"]
                    )
                    try Self.validate(target, for: id)
                    result[id] = target
                }
                return AlertSettingsSnapshot(
                    configuration: configuration,
                    priceTargets: targets
                )
            }
        }
    }

    func saveAlertSettings(_ snapshot: AlertSettingsSnapshot) throws {
        try Self.validate(snapshot.configuration)
        for (instrumentID, target) in snapshot.priceTargets {
            try Self.validate(target, for: instrumentID)
        }
        try databaseQueue.write { database in
            try database.execute(
                sql: """
                    UPDATE alert_settings SET
                        enabled = ?, basis = ?, rising_percent = ?, falling_percent = ?
                    WHERE singleton = 1
                    """,
                arguments: [
                    snapshot.configuration.isEnabled,
                    Self.alertBasisValue(snapshot.configuration.basis),
                    snapshot.configuration.risingThreshold,
                    snapshot.configuration.fallingThreshold,
                ]
            )
            try database.execute(sql: "DELETE FROM price_alerts")
            for (instrumentID, target) in snapshot.priceTargets where target.isEnabled {
                try database.execute(
                    sql: """
                        INSERT INTO price_alerts (instrument_id, rising_price, falling_price)
                        VALUES (?, ?, ?)
                        """,
                    arguments: [
                        instrumentID.rawValue,
                        target.risingPrice,
                        target.fallingPrice,
                    ]
                )
            }
        }
    }

    private static func validate(_ configuration: AlertConfiguration) throws {
        guard configuration.risingThreshold.isFinite,
            configuration.fallingThreshold.isFinite,
            (0.5...15).contains(configuration.risingThreshold),
            (0.5...15).contains(configuration.fallingThreshold)
        else {
            throw MarketDatabaseError.invalidAlertConfiguration
        }
    }

    private static func validate(
        _ target: PriceAlertTargets,
        for instrumentID: InstrumentID
    ) throws {
        guard target.isEnabled else {
            throw MarketDatabaseError.invalidPriceAlertTargets(
                instrumentID: instrumentID,
                violation: .missingPrices
            )
        }
        for (direction, price) in [
            (AlertDirection.rising, target.risingPrice),
            (.falling, target.fallingPrice),
        ] {
            guard let price else { continue }
            guard price.isFinite else {
                throw MarketDatabaseError.invalidPriceAlertTargets(
                    instrumentID: instrumentID,
                    violation: .nonFinite(direction)
                )
            }
            guard price > 0 else {
                throw MarketDatabaseError.invalidPriceAlertTargets(
                    instrumentID: instrumentID,
                    violation: .nonPositive(direction)
                )
            }
        }
    }

    static func validatedSessionDate(
        for snapshot: QuoteSnapshot,
        instrument: Instrument
    ) throws -> String {
        do {
            return try QuoteSnapshotValidator.validatedSessionDate(
                for: snapshot,
                instrument: instrument
            )
        } catch QuoteSnapshotValidationError.instrumentMismatch(let expected, let actual) {
            throw MarketDatabaseError.quoteInstrumentMismatch(
                expected: expected,
                actual: actual
            )
        } catch let error as QuoteSnapshotValidationError {
            throw MarketDatabaseError.invalidQuote(error.localizedDescription)
        }
    }

    private static func validateStoredSessionDate(
        _ storedSessionDate: String,
        for snapshot: QuoteSnapshot,
        instrument: Instrument
    ) throws {
        let expectedSessionDate = try validatedSessionDate(
            for: snapshot,
            instrument: instrument
        )
        guard storedSessionDate == expectedSessionDate else {
            throw MarketDatabaseError.quoteSessionDateMismatch(
                instrumentID: instrument.id,
                stored: storedSessionDate,
                derived: expectedSessionDate
            )
        }
    }

    private static func fetchWatchlist(from database: Database) throws -> [Instrument] {
        let rows = try Row.fetchAll(
            database,
            sql: """
                SELECT instrument_id, symbol, name, namespace, position
                FROM watchlist ORDER BY position
                """
        )
        var previousPosition: Int?
        return try rows.map { row in
            let storedID: String = row["instrument_id"]
            let namespaceValue: String = row["namespace"]
            guard let namespace = SymbolNamespace(rawValue: namespaceValue) else {
                throw MarketDatabaseError.invalidNamespace(namespaceValue)
            }
            let instrument = try Instrument(
                validatingSymbol: row["symbol"],
                name: row["name"],
                namespace: namespace
            )
            guard instrument.id.rawValue == storedID else {
                throw MarketDatabaseError.invalidInstrumentID(
                    expected: instrument.id,
                    stored: storedID
                )
            }
            let position: Int = row["position"]
            guard position >= 0,
                previousPosition.map({ position > $0 }) ?? true
            else {
                throw MarketDatabaseError.invalidWatchlist
            }
            previousPosition = position
            return instrument
        }
    }

    private static func normalizeWatchlistPositions(
        in writer: any DatabaseWriter,
        cancellationToken: DatabaseCancellationToken?
    ) throws {
        try writer.write { database in
            try DatabaseSchema.withCancellationProgressHandler(
                in: database,
                cancellationToken: cancellationToken
            ) {
                let rows = try Row.fetchAll(
                    database,
                    sql: "SELECT instrument_id, position FROM watchlist ORDER BY position"
                )
                let positions = rows.map { row -> Int in row["position"] }
                guard positions != Array(positions.indices) else { return }
                var usedPositions = Set(positions)
                for (position, row) in rows.enumerated() {
                    let currentPosition: Int = row["position"]
                    guard currentPosition != position else { continue }

                    if let displacedInstrumentID = try String.fetchOne(
                        database,
                        sql: "SELECT instrument_id FROM watchlist WHERE position = ?",
                        arguments: [position]
                    ) {
                        var scratchPosition = 0
                        while usedPositions.contains(scratchPosition) {
                            scratchPosition += 1
                        }
                        try database.execute(
                            sql: "UPDATE watchlist SET position = ? WHERE instrument_id = ?",
                            arguments: [scratchPosition, displacedInstrumentID]
                        )
                        usedPositions.remove(position)
                        usedPositions.insert(scratchPosition)
                    }

                    let instrumentID: String = row["instrument_id"]
                    try database.execute(
                        sql: "UPDATE watchlist SET position = ? WHERE instrument_id = ?",
                        arguments: [position, instrumentID]
                    )
                    usedPositions.remove(currentPosition)
                    usedPositions.insert(position)
                }
            }
        }
    }

    private static func configuration() -> Configuration {
        var configuration = Configuration()
        configuration.prepareDatabase { database in
            try database.execute(sql: "PRAGMA foreign_keys = ON")
            try database.execute(sql: "PRAGMA journal_mode = DELETE")
        }
        return configuration
    }

    private static func readOnlyConfiguration() -> Configuration {
        var configuration = Configuration()
        configuration.readonly = true
        configuration.prepareDatabase { database in
            try database.execute(sql: "PRAGMA foreign_keys = ON")
        }
        return configuration
    }

    private static func milliseconds(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1_000).rounded())
    }

    private static func date(fromMilliseconds milliseconds: Int64) -> Date {
        Date(timeIntervalSince1970: Double(milliseconds) / 1_000)
    }

    private static func sourceValue(_ source: QuoteSource) -> String {
        switch source {
        case .tencent: "tencent"
        case .eastMoney: "east_money"
        }
    }

    private static func quoteSource(from value: String) throws -> QuoteSource {
        switch value {
        case "tencent": .tencent
        case "east_money": .eastMoney
        default: throw MarketDatabaseError.invalidQuoteSource(value)
        }
    }

    private static func alertBasisValue(_ basis: AlertBasis) -> String {
        switch basis {
        case .percentage: "percentage"
        case .targetPrice: "target_price"
        }
    }

    private static func alertBasis(from value: String) throws -> AlertBasis {
        switch value {
        case "percentage": .percentage
        case "target_price": .targetPrice
        default: throw MarketDatabaseError.invalidAlertBasis(value)
        }
    }
}
