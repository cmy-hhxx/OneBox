import XCTest

@testable import StockWatchTool

final class MarketDatabaseTests: XCTestCase {
    func testWatchlistPositionsAtIntegerMaximumNormalizeWithoutOverflow() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "StockWatchPositionOverflow.\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent(MarketDatabase.defaultFileName).path
        let database = try MarketDatabase.open(atPath: path)
        let instruments = Array(Instrument.initialWatchlist.prefix(2))
        try await database.replaceWatchlist(with: instruments)
        try await database.close()

        try SQLiteTestSupport.execute(
            "UPDATE watchlist SET position = CASE instrument_id "
                + "WHEN '\(instruments[0].id.rawValue)' THEN 9223372036854775806 "
                + "WHEN '\(instruments[1].id.rawValue)' THEN 9223372036854775807 END;",
            atPath: path
        )

        let reopened = try MarketDatabase.open(atPath: path)
        let loaded = try await reopened.loadWatchlist()
        try await reopened.close()
        XCTAssertEqual(loaded, instruments)
        let positions = try SQLiteTestSupport.execute(
            "SELECT group_concat(position, ',') FROM watchlist ORDER BY position;",
            atPath: path
        )
        XCTAssertEqual(positions.trimmingCharacters(in: .whitespacesAndNewlines), "0,1")
    }

    func testDefaultWatchlistIsSeededOnlyOnFirstLaunch() async throws {
        let database = try MarketDatabase.inMemory()

        let firstLoad = try await database.loadWatchlist()
        XCTAssertEqual(firstLoad, Instrument.initialWatchlist)

        try await database.replaceWatchlist(with: [])

        let laterLoad = try await database.loadWatchlist()
        XCTAssertEqual(laterLoad, [])
    }

    func testWatchlistRoundTripsInUserDefinedOrder() async throws {
        let database = try MarketDatabase.inMemory()
        let watchlist = [
            Instrument(symbol: "AAPL", name: "苹果", namespace: .unitedStates),
            Instrument(symbol: "600519", name: "贵州茅台", namespace: .shanghai),
            Instrument(symbol: "00700", name: "腾讯控股", namespace: .hongKong),
        ]

        let initiallyLoaded = try await database.loadWatchlist()
        XCTAssertEqual(initiallyLoaded, Instrument.initialWatchlist)

        try await database.replaceWatchlist(with: watchlist)

        let loaded = try await database.loadWatchlist()
        XCTAssertEqual(loaded, watchlist)
    }

    func testWatchlistKeepsSameSymbolFromDifferentNamespaces() async throws {
        let database = try MarketDatabase.inMemory()
        let instruments = [
            Instrument(symbol: "000001", name: "上证指数", namespace: .shanghai),
            Instrument(symbol: "000001", name: "平安银行", namespace: .shenzhen),
        ]

        try await database.replaceWatchlist(with: instruments)

        let loaded = try await database.loadWatchlist()
        XCTAssertEqual(loaded, instruments)
    }

    func testReplacingWatchlistRemovesItemsThatAreNoLongerObserved() async throws {
        let database = try MarketDatabase.inMemory()
        let first = Instrument(symbol: "600519", name: "贵州茅台", namespace: .shanghai)
        let second = Instrument(symbol: "AAPL", name: "苹果", namespace: .unitedStates)

        try await database.replaceWatchlist(with: [first, second])
        try await database.replaceWatchlist(with: [second])

        let loaded = try await database.loadWatchlist()
        XCTAssertEqual(loaded, [second])
    }

    func testRemovingAnInstrumentCascadesItsAlertsAndQuoteCache() async throws {
        let database = try MarketDatabase.inMemory()
        let first = Instrument.initialWatchlist[0]
        let second = Instrument.initialWatchlist[2]
        try await database.replaceWatchlist(with: [first, second])
        try await database.saveQuote(
            quote(for: first, price: 1_500, at: "2026-07-30T07:00:00Z", source: .tencent),
            for: first
        )
        try await database.saveQuote(
            quote(for: second, price: 210, at: "2026-07-30T20:00:00Z", source: .tencent),
            for: second
        )
        try await database.saveAlertSettings(
            AlertSettingsSnapshot(
                configuration: .default,
                priceTargets: [
                    first.id: PriceAlertTargets(risingPrice: 1_600, fallingPrice: nil),
                    second.id: PriceAlertTargets(risingPrice: nil, fallingPrice: 200),
                ]
            )
        )

        try await database.replaceWatchlist(with: [second])

        let watchlist = try await database.loadWatchlist()
        let quotes = try await database.loadLatestQuotes(for: [first, second])
        let alerts = try await database.loadAlertSettings()
        XCTAssertEqual(watchlist, [second])
        XCTAssertEqual(
            quotes,
            [
                second.id: quote(
                    for: second, price: 210, at: "2026-07-30T20:00:00Z", source: .tencent)
            ])
        XCTAssertEqual(
            alerts.priceTargets,
            [second.id: PriceAlertTargets(risingPrice: nil, fallingPrice: 200)]
        )
    }

    func testLatestQuotesForEverySupportedMarketRoundTrip() async throws {
        let database = try MarketDatabase.inMemory()
        let instruments = Instrument.initialWatchlist
        try await database.replaceWatchlist(with: instruments)

        let snapshots = [
            quote(
                for: instruments[0],
                price: 1_500,
                at: "2026-07-30T07:00:00Z",
                source: .tencent
            ),
            quote(
                for: instruments[1],
                price: 510,
                at: "2026-07-30T08:00:00Z",
                source: .eastMoney
            ),
            quote(
                for: instruments[2],
                price: 210,
                at: "2026-07-30T20:00:00Z",
                source: .tencent
            ),
        ]

        for (instrument, snapshot) in zip(instruments, snapshots) {
            try await database.saveQuote(snapshot, for: instrument)
        }

        let loaded = try await database.loadLatestQuotes(for: instruments)
        let barCount = try await database.quoteBarCount()

        XCTAssertEqual(
            loaded, Dictionary(uniqueKeysWithValues: snapshots.map { ($0.instrumentID, $0) }))
        XCTAssertEqual(barCount, 3)
    }

    func testSavingTheSameSessionReplacesBarsAndClearRemovesAllQuoteData() async throws {
        let database = try MarketDatabase.inMemory()
        let instrument = Instrument.initialWatchlist[0]
        try await database.replaceWatchlist(with: [instrument])
        let first = quote(
            for: instrument,
            price: 1_500,
            at: "2026-07-30T07:00:00Z",
            source: .tencent
        )
        let replacement = quote(
            for: instrument,
            price: 1_510,
            at: "2026-07-30T07:01:00Z",
            source: .eastMoney
        )

        try await database.saveQuote(first, for: instrument)
        try await database.saveQuote(replacement, for: instrument)

        let replaced = try await database.loadLatestQuotes(for: [instrument])
        let replacedCount = try await database.quoteBarCount()
        XCTAssertEqual(replaced[instrument.id], replacement)
        XCTAssertEqual(replacedCount, 1)

        try await database.clearQuotes()

        let cleared = try await database.loadLatestQuotes(for: [instrument])
        let clearedCount = try await database.quoteBarCount()
        XCTAssertEqual(cleared, [:])
        XCTAssertEqual(clearedCount, 0)
    }

    func testSavingAQuoteRejectsAMismatchedInstrumentIdentity() async throws {
        let database = try MarketDatabase.inMemory()
        let expectedInstrument = Instrument.initialWatchlist[0]
        let otherInstrument = Instrument.initialWatchlist[2]
        let snapshot = quote(
            for: otherInstrument,
            price: 210,
            at: "2026-07-30T20:00:00Z",
            source: .tencent
        )

        do {
            try await database.saveQuote(snapshot, for: expectedInstrument)
            XCTFail("Expected MarketDatabase to reject a mismatched quote identity")
        } catch MarketDatabaseError.quoteInstrumentMismatch(let expected, let actual) {
            XCTAssertEqual(expected, expectedInstrument.id)
            XCTAssertEqual(actual, otherInstrument.id)
        }
    }

    func testQuoteIsNotSavedAfterInstrumentLeavesWatchlist() async throws {
        let database = try MarketDatabase.inMemory()
        let instrument = Instrument.initialWatchlist[0]
        try await database.replaceWatchlist(with: [instrument])
        try await database.replaceWatchlist(with: [])
        let snapshot = quote(
            for: instrument,
            price: 1_500,
            at: "2026-07-30T07:00:00Z",
            source: .tencent
        )

        let saved = try await database.saveQuote(snapshot, for: instrument)
        let barCount = try await database.quoteBarCount()

        XCTAssertFalse(saved)
        XCTAssertEqual(barCount, 0)
    }

    func testSavingAnExtendedSessionAppendsNewBarsAndRefreshesTheLastMinute() async throws {
        let database = try MarketDatabase.inMemory()
        let instrument = Instrument.initialWatchlist[0]
        try await database.replaceWatchlist(with: [instrument])
        let first = quote(
            for: instrument,
            prices: [1_500, 1_501],
            at: "2026-07-30T07:00:00Z",
            source: .tencent
        )
        let extended = quote(
            for: instrument,
            prices: [1_500, 1_502, 1_503],
            at: "2026-07-30T07:00:00Z",
            source: .tencent
        )

        try await database.saveQuote(first, for: instrument)
        try await database.saveQuote(extended, for: instrument)

        let loaded = try await database.loadLatestQuotes(for: [instrument])
        let barCount = try await database.quoteBarCount()
        XCTAssertEqual(loaded[instrument.id], extended)
        XCTAssertEqual(barCount, 3)
    }

    func testSameRangeSourceSwitchCorrectsEarlierBarsExactly() async throws {
        let database = try MarketDatabase.inMemory()
        let instrument = Instrument.initialWatchlist[0]
        try await database.replaceWatchlist(with: [instrument])
        let original = quote(
            for: instrument,
            prices: [1_500, 1_501, 1_502],
            at: "2026-07-30T07:00:00Z",
            source: .tencent
        )
        var correctedBars = original.minuteBars
        correctedBars[1] = MinuteBar(
            time: correctedBars[1].time,
            open: 1_510,
            close: 1_511,
            high: 1_512,
            low: 1_509
        )
        let corrected = replacing(
            original,
            bars: correctedBars,
            lastPrice: correctedBars.last?.close ?? original.lastPrice,
            source: .eastMoney
        )

        try await database.saveQuote(original, for: instrument)
        try await database.saveQuote(corrected, for: instrument)

        let loaded = try await database.loadLatestQuotes(for: [instrument])
        let count = try await database.quoteBarCount()
        XCTAssertEqual(loaded[instrument.id], corrected)
        XCTAssertEqual(count, 3)
    }

    func testShrinkingSnapshotDeletesOrphanedMinutes() async throws {
        let database = try MarketDatabase.inMemory()
        let instrument = Instrument.initialWatchlist[0]
        try await database.replaceWatchlist(with: [instrument])
        let original = quote(
            for: instrument,
            prices: [1_500, 1_501, 1_502],
            at: "2026-07-30T07:00:00Z",
            source: .tencent
        )
        let bars = Array(original.minuteBars.prefix(2))
        let shortened = replacing(
            original,
            bars: bars,
            lastPrice: bars.last?.close ?? original.lastPrice,
            source: .tencent
        )

        try await database.saveQuote(original, for: instrument)
        try await database.saveQuote(shortened, for: instrument)

        let loaded = try await database.loadLatestQuotes(for: [instrument])
        let count = try await database.quoteBarCount()
        XCTAssertEqual(loaded[instrument.id], shortened)
        XCTAssertEqual(count, 2)
    }

    func testNewTradingDayReplacesThePriorCache() async throws {
        let database = try MarketDatabase.inMemory()
        let instrument = Instrument.initialWatchlist[0]
        try await database.replaceWatchlist(with: [instrument])
        let first = quote(
            for: instrument,
            prices: [1_500, 1_501],
            at: "2026-07-30T07:00:00Z",
            source: .tencent
        )
        let nextDay = quote(
            for: instrument,
            prices: [1_600],
            at: "2026-07-31T07:00:00Z",
            source: .eastMoney
        )

        try await database.saveQuote(first, for: instrument)
        try await database.saveQuote(nextDay, for: instrument)

        let quotes = try await database.loadLatestQuotes(for: [instrument])
        let count = try await database.quoteBarCount()
        XCTAssertEqual(quotes, [instrument.id: nextDay])
        XCTAssertEqual(count, 1)
    }

    func testInvalidMinuteSnapshotIsRejectedWithoutPartialWrites() async throws {
        let database = try MarketDatabase.inMemory()
        let instrument = Instrument.initialWatchlist[0]
        try await database.replaceWatchlist(with: [instrument])
        let valid = quote(
            for: instrument,
            prices: [1_500, 1_501],
            at: "2026-07-30T07:00:00Z",
            source: .tencent
        )
        let duplicate = replacing(
            valid,
            bars: [valid.minuteBars[0], valid.minuteBars[0]],
            lastPrice: valid.lastPrice,
            source: valid.source
        )

        await assertThrowsErrorAsync {
            try await database.saveQuote(duplicate, for: instrument)
        }
        let count = try await database.quoteBarCount()
        let loaded = try await database.loadLatestQuotes(for: [instrument])
        XCTAssertEqual(count, 0)
        XCTAssertEqual(loaded, [:])
    }

    func testLoadingQuoteRejectsStoredSessionDateMismatch() async throws {
        let (directory, path, instrument) = try await makeStoredQuoteFixture(
            named: "StockWatchStoredSessionDate"
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        try SQLiteTestSupport.execute(
            "UPDATE quote_cache SET session_date = '2026-07-31';",
            atPath: path
        )
        let reopened = try MarketDatabase.open(atPath: path)

        do {
            try await reopened.validateLatestQuotes(for: [instrument])
            XCTFail("Expected stored session date mismatch to be rejected")
        } catch MarketDatabaseError.quoteSessionDateMismatch(
            let instrumentID,
            let stored,
            let derived
        ) {
            XCTAssertEqual(instrumentID, instrument.id)
            XCTAssertEqual(stored, "2026-07-31")
            XCTAssertEqual(derived, "2026-07-30")
        }
        try await reopened.close()
    }

    func testLoadingQuoteRejectsNonFiniteStoredQuote() async throws {
        let (directory, path, instrument) = try await makeStoredQuoteFixture(
            named: "StockWatchStoredQuote"
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        try SQLiteTestSupport.execute(
            "UPDATE quote_cache SET last_price = 1e999;",
            atPath: path
        )
        let reopened = try MarketDatabase.open(atPath: path)

        do {
            try await reopened.validateLatestQuotes(for: [instrument])
            XCTFail("Expected non-finite stored quote to be rejected")
        } catch MarketDatabaseError.invalidQuote {
            // Expected.
        }
        try await reopened.close()
    }

    func testLoadingQuoteRejectsNonFiniteStoredMinuteValues() async throws {
        let (directory, path, instrument) = try await makeStoredQuoteFixture(
            named: "StockWatchStoredMinute"
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        try SQLiteTestSupport.execute(
            "UPDATE minute_bars SET open = 1e999, close = 1e999, high = 1e999;",
            atPath: path
        )
        let reopened = try MarketDatabase.open(atPath: path)

        do {
            try await reopened.validateLatestQuotes(for: [instrument])
            XCTFail("Expected non-finite stored minute values to be rejected")
        } catch MarketDatabaseError.invalidQuote {
            // Expected.
        }
        try await reopened.close()
    }

    func testLoadingQuoteRejectsMinuteFromAnotherMarketSession() async throws {
        let (directory, path, instrument) = try await makeStoredQuoteFixture(
            named: "StockWatchStoredMinuteSession"
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        try SQLiteTestSupport.execute(
            "UPDATE minute_bars SET minute_at_ms = minute_at_ms + 86400000;",
            atPath: path
        )
        let reopened = try MarketDatabase.open(atPath: path)

        do {
            try await reopened.validateLatestQuotes(for: [instrument])
            XCTFail("Expected minute from another market session to be rejected")
        } catch MarketDatabaseError.invalidQuote {
            // Expected.
        }
        try await reopened.close()
    }

    func testLoadingQuotesOmitsOnlyTheInvalidCacheRow() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "StockWatchMixedCache-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent(MarketDatabase.defaultFileName).path
        let invalid = Instrument.initialWatchlist[0]
        let valid = Instrument(symbol: "600000", name: "浦发银行", namespace: .shanghai)
        let database = try MarketDatabase.open(atPath: path)
        try await database.replaceWatchlist(with: [invalid, valid])
        let invalidQuote = quote(
            for: invalid,
            prices: [1_500, 1_501],
            at: "2026-07-30T07:00:00Z",
            source: .tencent
        )
        let validQuote = quote(
            for: valid,
            prices: [10, 10.2],
            at: "2026-07-30T07:00:00Z",
            source: .eastMoney
        )
        try await database.saveQuote(invalidQuote, for: invalid)
        try await database.saveQuote(validQuote, for: valid)
        try await database.close()
        try SQLiteTestSupport.execute(
            "UPDATE quote_cache SET session_date = '2026-07-31' "
                + "WHERE instrument_id = '\(invalid.id.rawValue)';",
            atPath: path
        )

        let reopened = try MarketDatabase.open(atPath: path)
        let loaded = try await reopened.loadLatestQuotes(for: [invalid, valid])

        XCTAssertNil(loaded[invalid.id])
        XCTAssertEqual(loaded[valid.id], validQuote)
        try await reopened.close()
    }

    func testAlertConfigurationAndPerInstrumentTargetsRoundTrip() async throws {
        let database = try MarketDatabase.inMemory()
        let instrument = Instrument.initialWatchlist[2]
        try await database.replaceWatchlist(with: [instrument])

        let initialSettings = try await database.loadAlertSettings()
        XCTAssertEqual(initialSettings, .default)

        let configuration = AlertConfiguration(
            isEnabled: false,
            basis: .targetPrice,
            risingThreshold: 4.5,
            fallingThreshold: 2.5
        )
        let targets = PriceAlertTargets(risingPrice: 220, fallingPrice: 190)
        let settings = AlertSettingsSnapshot(
            configuration: configuration,
            priceTargets: [instrument.id: targets]
        )
        try await database.saveAlertSettings(settings)

        let loadedSettings = try await database.loadAlertSettings()
        XCTAssertEqual(loadedSettings, settings)
    }

    func testInvalidPriceTargetsAreRejectedBeforeSavingAndPreserveStoredSettings() async throws {
        let database = try MarketDatabase.inMemory()
        let instrument = Instrument.initialWatchlist[2]
        try await database.replaceWatchlist(with: [instrument])
        let original = AlertSettingsSnapshot(
            configuration: .default,
            priceTargets: [
                instrument.id: PriceAlertTargets(risingPrice: 220, fallingPrice: 190)
            ]
        )
        try await database.saveAlertSettings(original)

        let invalidTargets: [(PriceAlertTargets, PriceAlertTargetViolation)] = [
            (
                PriceAlertTargets(risingPrice: .infinity, fallingPrice: nil),
                .nonFinite(.rising)
            ),
            (
                PriceAlertTargets(risingPrice: .nan, fallingPrice: nil),
                .nonFinite(.rising)
            ),
            (
                PriceAlertTargets(risingPrice: 0, fallingPrice: nil),
                .nonPositive(.rising)
            ),
            (
                PriceAlertTargets(risingPrice: nil, fallingPrice: nil),
                .missingPrices
            ),
        ]

        for (target, expectedViolation) in invalidTargets {
            do {
                try await database.saveAlertSettings(
                    AlertSettingsSnapshot(
                        configuration: .default,
                        priceTargets: [instrument.id: target]
                    )
                )
                XCTFail("Invalid target should not be saved")
            } catch MarketDatabaseError.invalidPriceAlertTargets(
                let instrumentID,
                let violation
            ) {
                XCTAssertEqual(instrumentID, instrument.id)
                XCTAssertEqual(violation, expectedViolation)
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
            let preserved = try await database.loadAlertSettings()
            XCTAssertEqual(preserved, original)
        }
    }

    func testLoadingNonFiniteStoredPriceTargetFailsPrecisely() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("StockWatchStoredTarget.\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent(MarketDatabase.defaultFileName).path
        let instrument = Instrument.initialWatchlist[2]
        let database = try MarketDatabase.open(atPath: path)
        try await database.replaceWatchlist(with: [instrument])
        try await database.saveAlertSettings(
            AlertSettingsSnapshot(
                configuration: .default,
                priceTargets: [
                    instrument.id: PriceAlertTargets(risingPrice: 220, fallingPrice: nil)
                ]
            )
        )
        try await database.close()
        try SQLiteTestSupport.execute(
            "UPDATE price_alerts SET rising_price = 1e999;",
            atPath: path
        )
        let reopened = try MarketDatabase.open(atPath: path)

        do {
            _ = try await reopened.loadAlertSettings()
            XCTFail("Non-finite stored target should be rejected")
        } catch MarketDatabaseError.invalidPriceAlertTargets(
            let instrumentID,
            let violation
        ) {
            XCTAssertEqual(instrumentID, instrument.id)
            XCTAssertEqual(violation, .nonFinite(.rising))
        }
        try await reopened.close()
    }

    func testFileDatabaseReopensWithNamespaceWatchlistQuoteAndTargets() async throws {
        XCTAssertEqual(MarketDatabase.defaultFileName, "marketsprite.sqlite")
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("StockWatchTests.\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let databasePath =
            temporaryDirectory
            .appendingPathComponent(MarketDatabase.defaultFileName)
            .path
        let instruments = [
            Instrument(symbol: "000001", name: "上证指数", namespace: .shanghai),
            Instrument(symbol: "000001", name: "平安银行", namespace: .shenzhen),
        ]
        let snapshot = quote(
            for: instruments[0],
            price: 3_500,
            at: "2026-07-30T07:00:00Z",
            source: .tencent
        )
        let targets = PriceAlertTargets(risingPrice: 3_600, fallingPrice: 3_400)

        try await writeDatabaseFixture(
            atPath: databasePath,
            instruments: instruments,
            snapshot: snapshot,
            targets: targets
        )
        let reopened = try MarketDatabase.open(atPath: databasePath)
        let reopenedWatchlist = try await reopened.loadWatchlist()
        let reopenedQuotes = try await reopened.loadLatestQuotes(for: instruments)
        let reopenedSettings = try await reopened.loadAlertSettings()

        XCTAssertEqual(reopenedWatchlist, instruments)
        XCTAssertEqual(reopenedQuotes[instruments[0].id], snapshot)
        XCTAssertEqual(
            reopenedSettings.priceTargets,
            [instruments[0].id: targets]
        )
        try await reopened.close()
    }

    func testUnsupportedSchemaVersionIsRejected() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("StockWatchSchemaTests.\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("unsupported.sqlite").path
        try SQLiteTestSupport.execute(
            "PRAGMA application_id = \(DatabaseSchema.applicationID); PRAGMA user_version = 99;",
            atPath: path
        )

        XCTAssertThrowsError(try MarketDatabase.open(atPath: path)) { error in
            guard case MarketDatabaseError.unsupportedSchemaVersion(99) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testSchemaUsesFixedIdentityAndStrictConstraints() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("StockWatchSchemaIdentity.\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent(MarketDatabase.defaultFileName).path
        _ = try MarketDatabase.open(atPath: path)

        let schemaOutput = try SQLiteTestSupport.execute(
            """
            PRAGMA application_id;
            PRAGMA user_version;
            SELECT sql FROM sqlite_schema WHERE name = 'watchlist';
            """,
            atPath: path
        )
        XCTAssertTrue(
            schemaOutput.hasPrefix(
                "\(DatabaseSchema.applicationID)\n\(DatabaseSchema.version)\n"
            )
        )
        XCTAssertTrue(schemaOutput.uppercased().contains("STRICT"))
        XCTAssertTrue(schemaOutput.uppercased().contains("WITHOUT ROWID"))
        XCTAssertThrowsError(
            try SQLiteTestSupport.execute(
                "INSERT INTO alert_settings VALUES (2, 1, 'percentage', 3, 3);",
                atPath: path
            )
        )
        XCTAssertThrowsError(
            try SQLiteTestSupport.execute(
                "INSERT INTO price_alerts VALUES ('sse:600519', NULL, NULL);",
                atPath: path
            )
        )
    }

    func testSameVersionDatabaseMissingRequiredTableIsRejected() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("StockWatchMissingSchema.\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent(MarketDatabase.defaultFileName).path
        let database = try MarketDatabase.open(atPath: path)
        try await database.close()
        try SQLiteTestSupport.execute("DROP TABLE price_alerts;", atPath: path)

        XCTAssertThrowsError(try MarketDatabase.open(atPath: path)) { error in
            guard case MarketDatabaseError.invalidSchema(let detail) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertTrue(detail.contains("price_alerts"))
        }
    }

    func testSameVersionDatabaseWithAlteredConstraintIsRejected() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("StockWatchAlteredSchema.\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent(MarketDatabase.defaultFileName).path
        let database = try MarketDatabase.open(atPath: path)
        try await database.close()

        let alteredSQL = try SQLiteTestSupport.execute(
            """
            PRAGMA writable_schema = ON;
            UPDATE sqlite_schema
            SET sql = replace(
                sql,
                'CHECK(enabled IN (0, 1))',
                'CHECK(enabled IN (0, 1, 2))'
            )
            WHERE type = 'table' AND name = 'alert_settings';
            PRAGMA writable_schema = OFF;
            SELECT sql FROM sqlite_schema WHERE name = 'alert_settings';
            """,
            atPath: path
        )
        XCTAssertTrue(alteredSQL.contains("CHECK(enabled IN (0, 1, 2))"))

        XCTAssertThrowsError(try MarketDatabase.open(atPath: path)) { error in
            guard case MarketDatabaseError.invalidSchema(let detail) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertTrue(detail.contains("alert_settings"))
        }
    }

    func testUnexpectedTablesIndexesViewsAndTriggersAreRejected() async throws {
        let schemaObjects = [
            (
                "table",
                "CREATE TABLE copied_watchlist (instrument_id TEXT);"
            ),
            (
                "index",
                "CREATE INDEX watchlist_name_index ON watchlist(name);"
            ),
            (
                "view",
                "CREATE VIEW copied_watchlist AS SELECT * FROM watchlist;"
            ),
            (
                "trigger",
                """
                CREATE TRIGGER copy_watchlist AFTER INSERT ON watchlist BEGIN
                    DELETE FROM price_alerts WHERE instrument_id = new.instrument_id;
                END;
                """
            ),
        ]

        for (kind, sql) in schemaObjects {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("StockWatchUnexpectedSchema.\(UUID().uuidString)")
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            defer { try? FileManager.default.removeItem(at: directory) }
            let path = directory.appendingPathComponent(MarketDatabase.defaultFileName).path
            let database = try MarketDatabase.open(atPath: path)
            try await database.close()
            try SQLiteTestSupport.execute(sql, atPath: path)

            XCTAssertThrowsError(try MarketDatabase.open(atPath: path)) { error in
                guard case MarketDatabaseError.invalidSchema(let detail) = error else {
                    return XCTFail("Unexpected \(kind) error: \(error)")
                }
                XCTAssertTrue(detail.contains(kind), detail)
            }
        }
    }

    func testOpenInDirectoryCreatesFolderAndCanonicalDatabase() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("StockWatchDirectoryOpen.\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        let database = try MarketDatabase.openInDirectory(directory)

        XCTAssertEqual(
            database.databasePath,
            directory.appendingPathComponent(MarketDatabase.defaultFileName).path
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: database.databasePath))
        try await database.close()
    }

    private func quote(
        for instrument: Instrument,
        price: Double,
        at timestamp: String,
        source: QuoteSource
    ) -> QuoteSnapshot {
        quote(
            for: instrument,
            prices: [price],
            at: timestamp,
            source: source
        )
    }

    private func makeStoredQuoteFixture(
        named name: String
    ) async throws -> (directory: URL, path: String, instrument: Instrument) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name).\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let path = directory.appendingPathComponent(MarketDatabase.defaultFileName).path
        let instrument = Instrument.initialWatchlist[0]
        let database = try MarketDatabase.open(atPath: path)
        try await database.replaceWatchlist(with: [instrument])
        try await database.saveQuote(
            quote(
                for: instrument,
                price: 1_500,
                at: "2026-07-30T07:00:00Z",
                source: .tencent
            ),
            for: instrument
        )
        try await database.close()
        return (directory, path, instrument)
    }

    private func writeDatabaseFixture(
        atPath path: String,
        instruments: [Instrument],
        snapshot: QuoteSnapshot,
        targets: PriceAlertTargets
    ) async throws {
        let database = try MarketDatabase.open(atPath: path)
        try await database.replaceWatchlist(with: instruments)
        let saved = try await database.saveQuote(snapshot, for: instruments[0])
        XCTAssertTrue(saved)
        try await database.saveAlertSettings(
            AlertSettingsSnapshot(
                configuration: .default,
                priceTargets: [instruments[0].id: targets]
            )
        )
        try await database.close()
    }

    private func quote(
        for instrument: Instrument,
        prices: [Double],
        at timestamp: String,
        source: QuoteSource
    ) -> QuoteSnapshot {
        let marketTime = ISO8601DateFormatter().date(from: timestamp)!
        let bars = prices.enumerated().map { index, price in
            MinuteBar(
                time: marketTime.addingTimeInterval(Double(index) * 60),
                open: price - 1,
                close: price,
                high: price + 1,
                low: price - 2
            )
        }
        let lastPrice = prices.last ?? 0
        return QuoteSnapshot(
            instrumentID: instrument.id,
            minuteBars: bars,
            dayOpen: (prices.first ?? 0) - 1,
            previousClose: (prices.first ?? 0) - 2,
            lastPrice: lastPrice,
            marketTime: bars.last?.time ?? marketTime,
            receivedAt: (bars.last?.time ?? marketTime).addingTimeInterval(1),
            source: source
        )
    }

    private func replacing(
        _ snapshot: QuoteSnapshot,
        bars: [MinuteBar],
        lastPrice: Double,
        source: QuoteSource
    ) -> QuoteSnapshot {
        QuoteSnapshot(
            instrumentID: snapshot.instrumentID,
            minuteBars: bars,
            dayOpen: snapshot.dayOpen,
            previousClose: snapshot.previousClose,
            lastPrice: lastPrice,
            marketTime: bars.last?.time ?? snapshot.marketTime,
            receivedAt: snapshot.receivedAt,
            source: source
        )
    }

}

private func assertThrowsErrorAsync(
    _ expression: () async throws -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        try await expression()
        XCTFail("Expected expression to throw", file: file, line: line)
    } catch {
        // Expected.
    }
}
