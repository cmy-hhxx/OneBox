import XCTest

@testable import StockWatchTool

@MainActor
final class MonitorStoreTests: XCTestCase {
    func testStartReturnsAfterLocalRestoreWithoutWaitingForInitialRefresh() async throws {
        let database = try MarketDatabase.inMemory()
        let instrument = Instrument.initialWatchlist[2]
        let cached = makeQuote(for: instrument, price: 210)
        let refreshed = makeQuote(for: instrument, price: 215)
        try await database.replaceWatchlist(with: [instrument])
        try await database.saveQuote(cached, for: instrument)
        let client = OneShotSuspendingMarketDataClient()
        await client.suspendNextFetch(with: refreshed)
        let store = MonitorStore(
            client: client,
            database: database,
            preferences: makePreferences()
        )
        let startReturned = expectation(description: "start returned after local restore")
        let startTask = Task { @MainActor in
            try await store.start()
            startReturned.fulfill()
        }

        try await waitUntil("行情请求进入挂起点") { await client.isFetchSuspended }
        await fulfillment(of: [startReturned], timeout: 1)
        let restoredQuote = store.monitoredInstrument(for: instrument.id)?.quote

        await client.resumeSuspendedFetch()
        try await startTask.value
        await store.refreshAll()

        XCTAssertEqual(restoredQuote, cached)
        await store.stop()
    }

    func testCachedQuoteRemainsVisibleAndBecomesStaleWhenRefreshFails() async throws {
        let database = try MarketDatabase.inMemory()
        let instrument = Instrument.initialWatchlist[2]
        let cached = makeQuote(for: instrument, price: 210)
        try await database.replaceWatchlist(with: [instrument])
        try await database.saveQuote(cached, for: instrument)
        let store = MonitorStore(
            client: FailingMarketDataClient(),
            database: database,
            preferences: makePreferences()
        )

        try await store.start()
        await store.refreshAll()

        XCTAssertEqual(store.instruments, [instrument])
        XCTAssertEqual(store.monitoredInstrument(for: instrument.id)?.quote, cached)
        XCTAssertEqual(store.monitoredInstrument(for: instrument.id)?.status, .stale)
        XCTAssertEqual(
            store.sourceError,
            tr("行情连接暂不可用，已保留上次成功数据")
        )
        await store.stop()
    }

    func testNoIntradayDataDoesNotReportConnectionFailure() async throws {
        let database = try MarketDatabase.inMemory()
        let instrument = Instrument.initialWatchlist[0]
        let cached = makeQuote(for: instrument, price: 1_500)
        try await database.replaceWatchlist(with: [instrument])
        try await database.saveQuote(cached, for: instrument)
        let store = MonitorStore(
            client: NoIntradayDataMarketDataClient(),
            database: database,
            preferences: makePreferences()
        )

        try await store.start()
        await store.refreshAll()

        XCTAssertEqual(store.monitoredInstrument(for: instrument.id)?.quote, cached)
        XCTAssertEqual(store.monitoredInstrument(for: instrument.id)?.status, .stale)
        XCTAssertEqual(
            store.monitoredInstrument(for: instrument.id)?.statusMessage,
            tr("今天暂无分时数据")
        )
        XCTAssertNil(store.sourceError)
        await store.stop()
    }

    func testAddingMoreThanTenInstrumentsPersistsTheWholeWatchlist() async throws {
        let database = try MarketDatabase.inMemory()
        try await database.replaceWatchlist(with: [])
        let store = MonitorStore(
            client: FailingMarketDataClient(),
            database: database,
            preferences: makePreferences()
        )
        try await store.start()

        for index in 0..<12 {
            let instrument = Instrument(
                symbol: "TEST\(index)",
                name: "测试\(index)",
                namespace: .unitedStates
            )
            let error = await store.add(instrument)
            XCTAssertNil(error)
        }

        let persisted = try await database.loadWatchlist()
        XCTAssertEqual(store.instruments.count, 12)
        XCTAssertEqual(persisted, store.instruments)
        await store.stop()
    }

    func testConcurrentAddsPreserveEveryInstrument() async throws {
        let database = try MarketDatabase.inMemory()
        try await database.replaceWatchlist(with: [])
        let store = MonitorStore(
            client: FailingMarketDataClient(),
            database: database,
            preferences: makePreferences()
        )
        try await store.start()
        let instruments = (0..<20).map {
            Instrument(
                symbol: "RACE\($0)",
                name: "并发测试\($0)",
                namespace: .unitedStates
            )
        }

        await withTaskGroup(of: Void.self) { group in
            for instrument in instruments {
                group.addTask {
                    let error = await store.add(instrument)
                    XCTAssertNil(error)
                }
            }
        }

        let persisted = try await database.loadWatchlist()
        XCTAssertEqual(Set(store.instruments), Set(instruments))
        XCTAssertEqual(Set(persisted), Set(instruments))
        XCTAssertEqual(persisted, store.instruments)
        await store.stop()
    }

    func testImportReportsTheInvalidInstrumentIndex() async throws {
        let database = try MarketDatabase.inMemory()
        try await database.replaceWatchlist(with: [])
        let store = MonitorStore(
            client: FailingMarketDataClient(),
            database: database,
            preferences: makePreferences()
        )
        try await store.start()
        let json = #"""
            [
              {"symbol":"AAPL","name":"Apple","namespace":"us"},
              {"symbol":"12345","name":"无效 A 股","namespace":"sse"}
            ]
            """#

        let result = await store.importWatchlist(fromJSON: json)

        guard case .failure(let message) = result else {
            return XCTFail("Expected invalid import")
        }
        XCTAssertTrue(message.contains("2"))
        XCTAssertTrue(store.instruments.isEmpty)
        await store.stop()
    }

    func testEmptyJSONArrayAtomicallyClearsWatchlistTargetsAndQuoteCache() async throws {
        let database = try MarketDatabase.inMemory()
        let instrument = Instrument.initialWatchlist[2]
        let quote = makeQuote(for: instrument, price: 210)
        try await database.replaceWatchlist(with: [instrument])
        try await database.saveQuote(quote, for: instrument)
        try await database.saveAlertSettings(
            AlertSettingsSnapshot(
                configuration: .default,
                priceTargets: [
                    instrument.id: PriceAlertTargets(risingPrice: 220, fallingPrice: 200)
                ]
            )
        )
        let store = MonitorStore(
            client: FailingMarketDataClient(),
            database: database,
            preferences: makePreferences()
        )
        try await store.start()

        let result = await store.importWatchlist(fromJSON: "[]")
        await store.flushPendingPersistence()

        let persistedWatchlist = try await database.loadWatchlist()
        let persistedQuotes = try await database.loadLatestQuotes(for: [instrument])
        let persistedSettings = try await database.loadAlertSettings()
        let persistedTargets = persistedSettings.priceTargets
        XCTAssertEqual(result, .success(count: 0))
        XCTAssertTrue(store.instruments.isEmpty)
        XCTAssertEqual(persistedWatchlist, [])
        XCTAssertEqual(persistedQuotes, [:])
        XCTAssertEqual(persistedTargets, [:])
        await store.stop()
    }

    func testSuccessfulRefreshLeavesQuoteBarCountOffTheHotPath() async throws {
        let database = try MarketDatabase.inMemory()
        let instrument = Instrument.initialWatchlist[2]
        let quote = makeQuote(for: instrument, price: 210)
        try await database.replaceWatchlist(with: [instrument])
        let store = MonitorStore(
            client: StaticMarketDataClient(quote: quote),
            database: database,
            preferences: makePreferences()
        )

        try await store.start()
        await store.refreshAll()

        XCTAssertEqual(store.quoteBarCount, 0)
        await store.refreshQuoteBarCount()
        XCTAssertEqual(store.quoteBarCount, 2)
        await store.stop()
    }

    func testOneSuccessfulQuoteDoesNotHideAnotherQuotePersistenceFailure() async throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("StockWatchTests.\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let databasePath =
            temporaryDirectory
            .appendingPathComponent("mixed-quote-save.sqlite")
            .path
        let rejected = Instrument(
            symbol: "REJECTED",
            name: "拒绝写入",
            namespace: .unitedStates
        )
        let accepted = Instrument(
            symbol: "ACCEPTED",
            name: "允许写入",
            namespace: .unitedStates
        )
        try await prepareDatabase(
            atPath: databasePath,
            watchlist: [rejected, accepted]
        )
        let database = try MarketDatabase.open(atPath: databasePath)
        try SQLiteTestSupport.execute(
            """
            CREATE TRIGGER reject_one_quote
            BEFORE INSERT ON quote_cache
            WHEN NEW.instrument_id = 'us:REJECTED'
            BEGIN
                SELECT RAISE(ABORT, 'forced quote persistence failure');
            END;
            """,
            atPath: databasePath
        )
        let store = MonitorStore(
            client: PerInstrumentMarketDataClient(
                quotes: [
                    rejected.id: makeQuote(for: rejected, price: 110),
                    accepted.id: makeQuote(for: accepted, price: 120),
                ]
            ),
            database: database,
            preferences: makePreferences()
        )

        try await store.start()
        await store.refreshAll()

        XCTAssertNotNil(store.storageError)
        XCTAssertEqual(
            store.monitoredInstrument(for: rejected.id)?.quote?.lastPrice,
            110
        )
        XCTAssertEqual(
            store.monitoredInstrument(for: accepted.id)?.quote?.lastPrice,
            120
        )
        XCTAssertEqual(store.quoteBarCount, 0)
        await store.refreshQuoteBarCount()
        XCTAssertEqual(store.quoteBarCount, 2)
        XCTAssertNotNil(store.storageError)
        await store.stop()
        try await database.close()
    }

    func testOlderProviderSnapshotDoesNotReplaceNewerCachedQuote() async throws {
        let database = try MarketDatabase.inMemory()
        let instrument = Instrument.initialWatchlist[2]
        let cached = makeQuote(
            for: instrument,
            price: 210,
            at: Date(timeIntervalSince1970: 1_700_000_120)
        )
        let older = makeQuote(
            for: instrument,
            price: 205,
            at: Date(timeIntervalSince1970: 1_700_000_000)
        )
        try await database.replaceWatchlist(with: [instrument])
        try await database.saveQuote(cached, for: instrument)
        let store = MonitorStore(
            client: StaticMarketDataClient(quote: older),
            database: database,
            preferences: makePreferences()
        )

        try await store.start()
        await store.refreshAll()

        XCTAssertEqual(store.monitoredInstrument(for: instrument.id)?.quote, cached)
        XCTAssertEqual(store.monitoredInstrument(for: instrument.id)?.status, .stale)
        XCTAssertEqual(
            store.monitoredInstrument(for: instrument.id)?.statusMessage,
            tr("行情源返回了较旧数据")
        )
        await store.stop()
    }

    func testInvalidDuplicateMinuteSnapshotDoesNotReplaceCachedQuoteOrTriggerAlert() async throws {
        let database = try MarketDatabase.inMemory()
        let instrument = Instrument.initialWatchlist[2]
        let cached = makeQuote(
            for: instrument,
            price: 100,
            at: Date(timeIntervalSince1970: 1_700_000_120)
        )
        let valid = makeQuote(
            for: instrument,
            price: 110,
            at: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let invalid = QuoteSnapshot(
            instrumentID: instrument.id,
            minuteBars: [valid.minuteBars[0], valid.minuteBars[0]],
            dayOpen: valid.dayOpen,
            previousClose: valid.previousClose,
            lastPrice: valid.lastPrice,
            marketTime: valid.marketTime,
            receivedAt: valid.receivedAt,
            source: valid.source
        )
        try await database.replaceWatchlist(with: [instrument])
        try await database.saveQuote(cached, for: instrument)
        try await database.saveAlertSettings(
            AlertSettingsSnapshot(
                configuration: AlertConfiguration(
                    isEnabled: true,
                    basis: .targetPrice,
                    risingThreshold: 3,
                    fallingThreshold: 3
                ),
                priceTargets: [
                    instrument.id: PriceAlertTargets(
                        risingPrice: 105,
                        fallingPrice: nil
                    )
                ]
            )
        )
        let store = MonitorStore(
            client: StaticMarketDataClient(quote: invalid),
            database: database,
            preferences: makePreferences()
        )

        try await store.start()
        await store.refreshAll()

        XCTAssertEqual(store.monitoredInstrument(for: instrument.id)?.quote, cached)
        XCTAssertEqual(store.monitoredInstrument(for: instrument.id)?.status, .stale)
        let expectedError = MarketDatabaseError.invalidQuote(
            tr("分钟线时间必须严格递增且不能重复")
        ).localizedDescription
        XCTAssertFalse(expectedError.isEmpty)
        XCTAssertEqual(store.monitoredInstrument(for: instrument.id)?.statusMessage, expectedError)
        XCTAssertNil(store.activeAlert)
        XCTAssertNil(store.sourceError)
        let storedQuotes = try await database.loadLatestQuotes(for: [instrument])
        XCTAssertEqual(
            storedQuotes,
            [instrument.id: cached]
        )
        await store.stop()
    }

    func testMismatchedInstrumentSnapshotDoesNotReplaceCachedQuoteOrTriggerAlert() async throws {
        let database = try MarketDatabase.inMemory()
        let observed = Instrument(
            symbol: "OBSERVED",
            name: "观察标的",
            namespace: .unitedStates
        )
        let returned = Instrument(
            symbol: "RETURNED",
            name: "错误标的",
            namespace: .unitedStates
        )
        let cached = makeQuote(
            for: observed,
            price: 100,
            at: Date(timeIntervalSince1970: 1_700_000_120)
        )
        let mismatched = makeQuote(
            for: returned,
            price: 110,
            at: Date(timeIntervalSince1970: 1_700_000_000)
        )
        try await database.replaceWatchlist(with: [observed])
        try await database.saveQuote(cached, for: observed)
        try await database.saveAlertSettings(
            AlertSettingsSnapshot(
                configuration: AlertConfiguration(
                    isEnabled: true,
                    basis: .targetPrice,
                    risingThreshold: 3,
                    fallingThreshold: 3
                ),
                priceTargets: [
                    observed.id: PriceAlertTargets(
                        risingPrice: 105,
                        fallingPrice: nil
                    )
                ]
            )
        )
        let store = MonitorStore(
            client: StaticMarketDataClient(quote: mismatched),
            database: database,
            preferences: makePreferences()
        )

        try await store.start()
        await store.refreshAll()

        XCTAssertEqual(store.monitoredInstrument(for: observed.id)?.quote, cached)
        XCTAssertEqual(store.monitoredInstrument(for: observed.id)?.status, .stale)
        let expectedError = MarketDatabaseError.quoteInstrumentMismatch(
            expected: observed.id,
            actual: returned.id
        ).localizedDescription
        XCTAssertFalse(expectedError.isEmpty)
        XCTAssertEqual(store.monitoredInstrument(for: observed.id)?.statusMessage, expectedError)
        XCTAssertNil(store.activeAlert)
        XCTAssertNil(store.sourceError)
        let storedQuotes = try await database.loadLatestQuotes(for: [observed])
        XCTAssertEqual(
            storedQuotes,
            [observed.id: cached]
        )
        await store.stop()
    }

    func testMixedRefreshKeepsDomainRejectedQuoteLocalWhilePersistingValidQuote() async throws {
        let database = try MarketDatabase.inMemory()
        let rejected = Instrument(
            symbol: "REJECTED",
            name: "拒绝行情",
            namespace: .unitedStates
        )
        let accepted = Instrument(
            symbol: "ACCEPTED",
            name: "有效行情",
            namespace: .unitedStates
        )
        let cached = makeQuote(for: rejected, price: 100)
        let validRejectedQuote = makeQuote(for: rejected, price: 110)
        let invalid = QuoteSnapshot(
            instrumentID: rejected.id,
            minuteBars: [
                validRejectedQuote.minuteBars[0],
                validRejectedQuote.minuteBars[0],
            ],
            dayOpen: validRejectedQuote.dayOpen,
            previousClose: validRejectedQuote.previousClose,
            lastPrice: validRejectedQuote.lastPrice,
            marketTime: validRejectedQuote.marketTime,
            receivedAt: validRejectedQuote.receivedAt,
            source: validRejectedQuote.source
        )
        let valid = makeQuote(for: accepted, price: 120)
        try await database.replaceWatchlist(with: [rejected, accepted])
        try await database.saveQuote(cached, for: rejected)
        try await database.saveAlertSettings(
            AlertSettingsSnapshot(
                configuration: AlertConfiguration(
                    isEnabled: true,
                    basis: .targetPrice,
                    risingThreshold: 3,
                    fallingThreshold: 3
                ),
                priceTargets: [
                    rejected.id: PriceAlertTargets(
                        risingPrice: 105,
                        fallingPrice: nil
                    )
                ]
            )
        )
        let store = MonitorStore(
            client: PerInstrumentMarketDataClient(
                quotes: [rejected.id: invalid, accepted.id: valid]
            ),
            database: database,
            preferences: makePreferences()
        )

        try await store.start()
        await store.refreshAll()

        let expectedError = MarketDatabaseError.invalidQuote(
            tr("分钟线时间必须严格递增且不能重复")
        ).localizedDescription
        XCTAssertEqual(store.monitoredInstrument(for: rejected.id)?.quote, cached)
        XCTAssertEqual(store.monitoredInstrument(for: rejected.id)?.status, .stale)
        XCTAssertEqual(store.monitoredInstrument(for: rejected.id)?.statusMessage, expectedError)
        XCTAssertEqual(store.monitoredInstrument(for: accepted.id)?.quote, valid)
        XCTAssertEqual(store.monitoredInstrument(for: accepted.id)?.status, .live)
        XCTAssertNil(store.activeAlert)
        XCTAssertNil(store.sourceError)
        XCTAssertNil(store.storageError)
        let storedQuotes = try await database.loadLatestQuotes(for: [rejected, accepted])
        XCTAssertEqual(storedQuotes, [rejected.id: cached, accepted.id: valid])
        await store.stop()
    }

    func testChangingOnePriceTargetDoesNotRearmOtherInstruments() async throws {
        let database = try MarketDatabase.inMemory()
        let first = Instrument(symbol: "AAA", name: "甲", namespace: .unitedStates)
        let second = Instrument(symbol: "BBB", name: "乙", namespace: .unitedStates)
        let firstQuote = makeQuote(for: first, price: 110)
        let secondQuote = makeQuote(for: second, price: 110)
        try await database.replaceWatchlist(with: [first, second])
        try await database.saveAlertSettings(
            AlertSettingsSnapshot(
                configuration: AlertConfiguration(
                    isEnabled: true,
                    basis: .targetPrice,
                    risingThreshold: 3,
                    fallingThreshold: 3
                ),
                priceTargets: [
                    first.id: PriceAlertTargets(risingPrice: 105, fallingPrice: nil),
                    second.id: PriceAlertTargets(risingPrice: 105, fallingPrice: nil),
                ]
            )
        )
        let store = MonitorStore(
            client: PerInstrumentMarketDataClient(
                quotes: [first.id: firstQuote, second.id: secondQuote]
            ),
            database: database,
            preferences: makePreferences()
        )
        try await store.start()
        await store.refreshAll()
        XCTAssertEqual(store.activeAlert?.instrument.id, first.id)
        XCTAssertEqual(store.pendingAlertCountForTesting, 1)

        store.updatePriceTargets(
            for: first,
            risingPrice: 106,
            fallingPrice: nil
        )
        XCTAssertEqual(store.activeAlert?.instrument.id, second.id)
        XCTAssertEqual(store.pendingAlertCountForTesting, 0)

        await store.refreshAll()
        XCTAssertEqual(store.activeAlert?.instrument.id, second.id)
        XCTAssertEqual(store.pendingAlertCountForTesting, 1)
        store.dismissActiveAlert()
        XCTAssertEqual(store.activeAlert?.instrument.id, first.id)
        XCTAssertEqual(store.pendingAlertCountForTesting, 0)
        await store.stop()
    }

    func testAlertPersistenceFailureRollsBackAndSurvivesEmptyRefresh() async throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("StockWatchTests.\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let databasePath =
            temporaryDirectory
            .appendingPathComponent("readonly.sqlite")
            .path
        var writableDatabase: MarketDatabase? = try MarketDatabase.open(
            atPath: databasePath
        )
        try await writableDatabase?.replaceWatchlist(with: [])
        try await writableDatabase?.close()
        writableDatabase = nil
        let database = try MarketDatabase.openReadOnly(atPath: databasePath)
        let store = MonitorStore(
            client: FailingMarketDataClient(),
            database: database,
            preferences: makePreferences()
        )
        try await store.start()
        let persisted = store.alertConfiguration
        var changed = persisted
        changed.isEnabled.toggle()

        store.updateAlertConfiguration(changed)
        try await waitUntil("提醒设置失败回滚") {
            store.storageError != nil
        }

        XCTAssertEqual(store.alertConfiguration, persisted)
        XCTAssertNotNil(store.storageError)
        await store.refreshAll()
        XCTAssertNotNil(store.storageError)
        await store.stop()
        try await database.close()
    }

    func testStaleSuccessfulAlertSaveBecomesRollbackBaselineBeforeLaterSaveFails() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("StockWatchTests.\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("alert-settings.sqlite").path
        let instrument = Instrument.initialWatchlist[2]
        let initial = AlertSettingsSnapshot(
            configuration: AlertConfiguration(
                isEnabled: true,
                basis: .targetPrice,
                risingThreshold: 3,
                fallingThreshold: 3
            ),
            priceTargets: [
                instrument.id: PriceAlertTargets(risingPrice: 101, fallingPrice: 99)
            ]
        )
        let committed = AlertSettingsSnapshot(
            configuration: AlertConfiguration(
                isEnabled: true,
                basis: .targetPrice,
                risingThreshold: 5,
                fallingThreshold: 2
            ),
            priceTargets: [
                instrument.id: PriceAlertTargets(risingPrice: 105, fallingPrice: 95)
            ]
        )
        let rejected = AlertSettingsSnapshot(
            configuration: AlertConfiguration(
                isEnabled: true,
                basis: .targetPrice,
                risingThreshold: 7,
                fallingThreshold: 2
            ),
            priceTargets: [
                instrument.id: PriceAlertTargets(risingPrice: 107, fallingPrice: 93)
            ]
        )
        let preparedDatabase = try MarketDatabase.open(atPath: path)
        try await preparedDatabase.replaceWatchlist(with: [instrument])
        try await preparedDatabase.saveAlertSettings(initial)
        try await preparedDatabase.close()
        let database = try MarketDatabase.open(atPath: path)
        try SQLiteTestSupport.execute(
            """
            CREATE TRIGGER reject_alert_settings_b
            BEFORE UPDATE OF rising_percent ON alert_settings
            WHEN NEW.rising_percent = 7.0
            BEGIN
                SELECT RAISE(ABORT, 'forced alert settings persistence failure');
            END;
            """,
            atPath: path
        )
        let store = MonitorStore(
            client: FailingMarketDataClient(),
            database: database,
            preferences: makePreferences()
        )
        try await store.start()
        let probe = AlertSettingsPersistenceProbe(blockingCommittedSnapshot: committed)
        store.alertSettingsPersistenceEventObserverForTesting = { event in
            await probe.receive(event)
        }

        store.updateAlertConfiguration(committed.configuration)
        store.updatePriceTargets(
            for: instrument,
            risingPrice: committed.priceTargets[instrument.id]?.risingPrice,
            fallingPrice: committed.priceTargets[instrument.id]?.fallingPrice
        )
        let committedEvent = await probe.nextEvent()
        let committedSnapshot: AlertSettingsSnapshot?
        switch committedEvent {
        case .committed(let snapshot, _):
            committedSnapshot = snapshot
        default:
            committedSnapshot = nil
        }
        XCTAssertEqual(committedSnapshot, committed)

        store.updateAlertConfiguration(rejected.configuration)
        store.updatePriceTargets(
            for: instrument,
            risingPrice: rejected.priceTargets[instrument.id]?.risingPrice,
            fallingPrice: rejected.priceTargets[instrument.id]?.fallingPrice
        )
        await probe.releaseBlockedCommit()
        let finishedEvent = await probe.nextEvent()
        let finishedSnapshot: AlertSettingsSnapshot?
        switch finishedEvent {
        case .finished(let snapshot, _):
            finishedSnapshot = snapshot
        default:
            finishedSnapshot = nil
        }
        XCTAssertEqual(finishedSnapshot, committed)
        await store.flushPendingPersistence()
        try SQLiteTestSupport.execute(
            "DROP TRIGGER reject_alert_settings_b;",
            atPath: path
        )

        XCTAssertEqual(store.alertConfiguration, committed.configuration)
        XCTAssertEqual(store.priceAlertTargets, committed.priceTargets)
        XCTAssertNotEqual(store.alertConfiguration, initial.configuration)
        XCTAssertNotEqual(store.priceAlertTargets, initial.priceTargets)
        XCTAssertTrue(
            store.storageError?.contains(tr("提醒设置保存失败，已恢复上次保存值")) == true
        )
        await store.stop()
        try await database.close()

        let reopened = try MarketDatabase.open(atPath: path)
        let persisted = try await reopened.loadAlertSettings()
        XCTAssertEqual(persisted, committed)
        XCTAssertEqual(
            AlertSettingsSnapshot(
                configuration: store.alertConfiguration,
                priceTargets: store.priceAlertTargets
            ),
            persisted
        )
        try await reopened.close()
    }

    func testShutdownDrainsReplacedAlertSettingsPersistenceLineage() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("StockWatchTests.\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("alert-settings.sqlite").path
        let initial = AlertSettingsSnapshot(
            configuration: AlertConfiguration(
                isEnabled: true,
                basis: .percentage,
                risingThreshold: 3,
                fallingThreshold: 3
            ),
            priceTargets: [:]
        )
        let replacement = AlertSettingsSnapshot(
            configuration: AlertConfiguration(
                isEnabled: true,
                basis: .percentage,
                risingThreshold: 5,
                fallingThreshold: 2
            ),
            priceTargets: [:]
        )
        let preparedDatabase = try MarketDatabase.open(atPath: path)
        try await preparedDatabase.saveAlertSettings(initial)
        try await preparedDatabase.close()

        let database = try MarketDatabase.open(atPath: path)
        let closeProbe = DatabaseCloseProbe()
        let store = MonitorStore(
            client: FailingMarketDataClient(),
            database: database,
            preferences: makePreferences(),
            databaseClose: { try await closeProbe.close($0) }
        )
        try await store.start()
        let probe = AlertSettingsPersistenceProbe(
            blockingCommittedSnapshot: replacement
        )
        store.alertSettingsPersistenceEventObserverForTesting = { event in
            await probe.receive(event)
        }

        store.updateAlertConfiguration(replacement.configuration)
        let committedEvent = await probe.nextEvent()
        let committedSnapshot: AlertSettingsSnapshot?
        switch committedEvent {
        case .committed(let snapshot, _):
            committedSnapshot = snapshot
        default:
            committedSnapshot = nil
        }
        XCTAssertEqual(committedSnapshot, replacement)

        store.updateAlertConfiguration(initial.configuration)
        let shutdownTask = Task { @MainActor in
            await store.shutdown()
        }
        try await waitUntil("停机先关闭操作准入") {
            !store.acceptsOperationsForTesting
        }
        let closeCountWhileLineageIsBlocked = await closeProbe.closeCount
        XCTAssertEqual(closeCountWhileLineageIsBlocked, 0)

        await probe.releaseBlockedCommit()
        let finishedEvent = await probe.nextEvent()
        let finishedSnapshot: AlertSettingsSnapshot?
        switch finishedEvent {
        case .finished(let snapshot, _):
            finishedSnapshot = snapshot
        default:
            finishedSnapshot = nil
        }
        let flushDisposition = await probe.nextEvent()
        let awaitedLineageSnapshot: AlertSettingsSnapshot?
        switch flushDisposition {
        case .flushAwaitingLineage(let snapshot, _):
            awaitedLineageSnapshot = snapshot
        default:
            awaitedLineageSnapshot = nil
        }
        let shutdownFailure = await shutdownTask.value
        XCTAssertNil(shutdownFailure)
        let finalCloseCount = await closeProbe.closeCount
        XCTAssertEqual(finalCloseCount, 1)

        let finalUISnapshot = AlertSettingsSnapshot(
            configuration: store.alertConfiguration,
            priceTargets: store.priceAlertTargets
        )
        let finalStorageError = store.storageError
        let reopened = try MarketDatabase.open(atPath: path)
        let persisted = try await reopened.loadAlertSettings()
        try await reopened.close()

        XCTAssertEqual(awaitedLineageSnapshot, initial)
        XCTAssertEqual(finishedSnapshot, replacement)
        XCTAssertEqual(persisted, initial)
        XCTAssertNotEqual(persisted, replacement)
        XCTAssertEqual(finalUISnapshot, initial)
        XCTAssertNil(finalStorageError)
    }

    func testRemovedInstrumentCannotCommitDelayedRefresh() async throws {
        let database = try MarketDatabase.inMemory()
        let instrument = Instrument(
            symbol: "REMOVE",
            name: "待删除",
            namespace: .unitedStates
        )
        try await database.replaceWatchlist(with: [instrument])
        try await database.saveAlertSettings(
            AlertSettingsSnapshot(
                configuration: AlertConfiguration(
                    isEnabled: true,
                    basis: .targetPrice,
                    risingThreshold: 3,
                    fallingThreshold: 3
                ),
                priceTargets: [
                    instrument.id: PriceAlertTargets(risingPrice: 100, fallingPrice: nil)
                ]
            )
        )
        let client = OneShotSuspendingMarketDataClient()
        let store = MonitorStore(
            client: client,
            database: database,
            preferences: makePreferences()
        )
        try await store.start()
        await store.refreshAll()
        await client.suspendNextFetch(
            with: makeQuote(for: instrument, price: 110)
        )
        let refreshTask = Task { await store.refreshAll() }
        try await waitUntil("行情请求进入挂起点") { await client.isFetchSuspended }

        await store.remove(instrument)
        await client.resumeSuspendedFetch()
        _ = await refreshTask.value
        let quoteBarCount = try await database.quoteBarCount()

        XCTAssertTrue(store.instruments.isEmpty)
        XCTAssertNil(store.monitoredInstrument(for: instrument.id))
        XCTAssertNil(store.activeAlert)
        XCTAssertEqual(quoteBarCount, 0)
        await store.stop()
    }

    func testImportedWatchlistCannotCommitDiscardedInstrumentDelayedRefresh() async throws {
        let database = try MarketDatabase.inMemory()
        let discarded = Instrument(
            symbol: "OLD",
            name: "旧标的",
            namespace: .unitedStates
        )
        let imported = Instrument(
            symbol: "NEW",
            name: "新标的",
            namespace: .unitedStates
        )
        try await database.replaceWatchlist(with: [discarded])
        try await database.saveAlertSettings(
            AlertSettingsSnapshot(
                configuration: AlertConfiguration(
                    isEnabled: true,
                    basis: .targetPrice,
                    risingThreshold: 3,
                    fallingThreshold: 3
                ),
                priceTargets: [
                    discarded.id: PriceAlertTargets(risingPrice: 100, fallingPrice: nil)
                ]
            )
        )
        let client = OneShotSuspendingMarketDataClient()
        let store = MonitorStore(
            client: client,
            database: database,
            preferences: makePreferences()
        )
        try await store.start()
        await store.refreshAll()
        await client.suspendNextFetch(
            with: makeQuote(for: discarded, price: 110)
        )
        let refreshTask = Task { await store.refreshAll() }
        try await waitUntil("行情请求进入挂起点") { await client.isFetchSuspended }
        let json = String(
            data: try JSONEncoder().encode([imported]),
            encoding: .utf8
        )!

        let result = await store.importWatchlist(fromJSON: json)
        await client.resumeSuspendedFetch()
        _ = await refreshTask.value
        let quoteBarCount = try await database.quoteBarCount()

        XCTAssertEqual(result, .success(count: 1))
        XCTAssertEqual(store.instruments, [imported])
        XCTAssertNil(store.monitoredInstrument(for: discarded.id))
        XCTAssertNil(store.activeAlert)
        XCTAssertEqual(quoteBarCount, 0)
        await store.stop()
    }

    func testStaleCacheCannotEnableOrGenerateTargetsAsCurrentPrice() async throws {
        let database = try MarketDatabase.inMemory()
        let instrument = Instrument.initialWatchlist[2]
        let cached = makeQuote(for: instrument, price: 210)
        try await database.replaceWatchlist(with: [instrument])
        try await database.saveQuote(cached, for: instrument)
        let store = MonitorStore(
            client: FailingMarketDataClient(),
            database: database,
            preferences: makePreferences()
        )
        try await store.start()
        await store.refreshAll()

        XCTAssertEqual(store.monitoredInstrument(for: instrument.id)?.status, .stale)
        XCTAssertFalse(store.setPriceTargetsEnabled(for: instrument, enabled: true))
        let generatedCount = await store.generatePriceTargetsFromCurrentQuotes()
        XCTAssertEqual(generatedCount, 0)
        XCTAssertTrue(store.priceAlertTargets.isEmpty)
        await store.stop()
    }

    func testPreviousSessionQuoteStaysStaleAndNeverTriggersAlertWithOrWithoutCache()
        async throws
    {
        let formatter = ISO8601DateFormatter()
        let quoteTime = try XCTUnwrap(formatter.date(from: "2026-08-27T14:30:00Z"))
        let now = try XCTUnwrap(formatter.date(from: "2026-08-28T14:30:00Z"))
        let instrument = Instrument.initialWatchlist[2]
        let quote = makeQuote(for: instrument, price: 210, at: quoteTime)

        for preloadsCache in [false, true] {
            let database = try MarketDatabase.inMemory()
            try await database.replaceWatchlist(with: [instrument])
            if preloadsCache {
                try await database.saveQuote(quote, for: instrument)
            }
            try await database.saveAlertSettings(
                AlertSettingsSnapshot(
                    configuration: AlertConfiguration(
                        isEnabled: true,
                        basis: .percentage,
                        risingThreshold: 0.5,
                        fallingThreshold: 0.5
                    ),
                    priceTargets: [:]
                )
            )
            let store = MonitorStore(
                client: StaticMarketDataClient(quote: quote),
                database: database,
                preferences: makePreferences(),
                refreshNow: { _ in now }
            )

            try await store.start()
            await store.refreshAll()

            let monitored = try XCTUnwrap(store.monitoredInstrument(for: instrument.id))
            XCTAssertEqual(monitored.quote, quote)
            XCTAssertEqual(monitored.status, .stale)
            XCTAssertEqual(monitored.statusMessage, "行情源返回了非当前交易日数据")
            XCTAssertNil(store.activeAlert)
            XCTAssertEqual(store.pendingAlertCountForTesting, 0)
            let persisted = try await database.loadLatestQuotes(for: [instrument])
            XCTAssertEqual(persisted[instrument.id], quote)
            await store.stop()
        }
    }

    func testConcurrentRefreshesShareOneBatchAndRespectConcurrencyLimit() async throws {
        let database = try MarketDatabase.inMemory()
        let instruments = (0..<12).map { index in
            Instrument(
                symbol: "LIMIT\(index)",
                name: "并发上限 \(index)",
                namespace: .unitedStates
            )
        }
        try await database.replaceWatchlist(with: instruments)
        let client = CountingMarketDataClient()
        let store = MonitorStore(
            client: client,
            database: database,
            preferences: makePreferences(),
            maximumConcurrentRefreshes: 6
        )
        try await store.start()
        await store.refreshAll()
        await client.resetMetrics()
        await client.suspendRequests()

        let first = Task { @MainActor in await store.refreshAll() }
        let second = Task { @MainActor in await store.refreshAll() }
        try await waitUntil("刷新达到并发请求上限") {
            await client.metrics().maximumActiveRequests == 6
        }
        await client.resumeRequests()
        _ = await first.value
        _ = await second.value

        let metrics = await client.metrics()
        XCTAssertEqual(metrics.requestCount, instruments.count)
        XCTAssertLessThanOrEqual(metrics.maximumActiveRequests, 6)
        await store.stop()
    }

    func testReorderingDoesNotTriggerAnotherRefreshBatch() async throws {
        let database = try MarketDatabase.inMemory()
        let instruments = [
            Instrument(symbol: "MOVEA", name: "甲", namespace: .unitedStates),
            Instrument(symbol: "MOVEB", name: "乙", namespace: .unitedStates),
        ]
        try await database.replaceWatchlist(with: instruments)
        let client = CountingMarketDataClient()
        let store = MonitorStore(
            client: client,
            database: database,
            preferences: makePreferences()
        )
        try await store.start()
        await store.refreshAll()
        await client.resetMetrics()

        await store.moveInstruments(from: IndexSet(integer: 0), to: 2)

        let metrics = await client.metrics()
        XCTAssertEqual(metrics.requestCount, 0)
        XCTAssertEqual(store.instruments, [instruments[1], instruments[0]])
        await store.stop()
    }

    func testAlertDismissalPausePreservesActualRemainingCountdown() async throws {
        let timing = AlertDismissalTimingProbe()
        let store = MonitorStore(
            database: try MarketDatabase.inMemory(),
            preferences: makePreferences(),
            alertDismissalDelay: .seconds(6),
            alertDismissalNow: { timing.now },
            alertDismissalSleep: { try await timing.sleep(for: $0) }
        )

        store.testAlert(.rising)
        try await waitUntil("首次提醒倒计时开始") {
            timing.requestedSleeps.count == 1
        }
        timing.advance(by: .seconds(2))
        store.setAlertDismissalPaused(true)
        timing.advance(by: .seconds(20))
        XCTAssertNotNil(store.activeAlert)

        store.setAlertDismissalPaused(false)
        try await waitUntil("恢复后的提醒倒计时开始") {
            timing.requestedSleeps.count == 2
        }
        XCTAssertEqual(timing.requestedSleeps, [.seconds(6), .seconds(4)])
        timing.completeLatestSleep()
        try await waitUntil("剩余倒计时结束后提醒消失") {
            store.activeAlert == nil
        }

        store.testAlert(.falling)
        store.dismissActiveAlert()
        XCTAssertNil(store.activeAlert)
    }

    func testShutdownReturnsTypedPendingSettingsFlushFailure() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("StockWatchShutdownFailureTests.\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("readonly.sqlite").path
        let writableDatabase = try MarketDatabase.open(atPath: path)
        try await writableDatabase.close()
        let database = try MarketDatabase.openReadOnly(atPath: path)
        let store = MonitorStore(
            client: FailingMarketDataClient(),
            database: database,
            preferences: makePreferences()
        )
        try await store.start()
        var changedConfiguration = store.alertConfiguration
        changedConfiguration.isEnabled.toggle()
        store.updateAlertConfiguration(changedConfiguration)

        let shutdownFailure = await store.shutdown()

        XCTAssertNotNil(shutdownFailure?.pendingSettingsFlushMessage)
        XCTAssertNil(shutdownFailure?.databaseCloseMessage)
        XCTAssertEqual(shutdownFailure?.databasePath, path)
    }

    func testShutdownDrainsRefreshBeforeCloseAndRejectsPostStopRefresh() async throws {
        let database = try MarketDatabase.inMemory()
        let instrument = Instrument.initialWatchlist[2]
        try await database.replaceWatchlist(with: [instrument])
        let client = OneShotSuspendingMarketDataClient()
        await client.suspendNextFetch(
            with: makeQuote(for: instrument, price: 215)
        )
        let closeProbe = DatabaseCloseProbe()
        let store = MonitorStore(
            client: client,
            database: database,
            preferences: makePreferences(),
            databaseClose: { try await closeProbe.close($0) }
        )
        try await store.start()
        try await waitUntil("行情请求进入挂起点") { await client.isFetchSuspended }

        let shutdownTask = Task { @MainActor in
            await store.shutdown()
        }
        try await waitUntil("停机关闭操作准入") {
            !store.acceptsOperationsForTesting
        }
        let closeCountWhileRefreshIsSuspended = await closeProbe.closeCount
        XCTAssertEqual(closeCountWhileRefreshIsSuspended, 0)

        await client.resumeSuspendedFetch()
        let shutdownFailure = await shutdownTask.value
        XCTAssertNil(shutdownFailure)
        let closeCountAfterDrain = await closeProbe.closeCount
        XCTAssertEqual(closeCountAfterDrain, 1)
        let fetchCountAfterShutdown = await client.fetchCount

        await store.refreshAll()
        let generatedCount = await store.generatePriceTargetsFromCurrentQuotes()

        let finalFetchCount = await client.fetchCount
        XCTAssertEqual(finalFetchCount, fetchCountAfterShutdown)
        XCTAssertNil(generatedCount)
    }

    func testClearQuoteHistoryDrainsInFlightRefreshBeforeDeletingCache() async throws {
        let database = try MarketDatabase.inMemory()
        let instrument = Instrument.initialWatchlist[2]
        let cached = makeQuote(for: instrument, price: 210)
        let refreshed = makeQuote(
            for: instrument,
            price: 215,
            at: cached.marketTime.addingTimeInterval(60)
        )
        try await database.replaceWatchlist(with: [instrument])
        try await database.saveQuote(cached, for: instrument)
        let client = OneShotSuspendingMarketDataClient()
        await client.suspendNextFetch(with: refreshed)
        let store = MonitorStore(
            client: client,
            database: database,
            preferences: makePreferences()
        )
        try await store.start()
        try await waitUntil("清缓存前刷新进入挂起点") { await client.isFetchSuspended }

        let clearTask = Task { @MainActor in
            await store.clearQuoteHistory()
        }
        try await waitUntil("清缓存等待在途刷新") {
            store.isClearingQuoteHistoryForTesting
        }
        let countWhileRefreshIsSuspended = try await database.quoteBarCount()
        XCTAssertEqual(countWhileRefreshIsSuspended, 2)

        await client.resumeSuspendedFetch()
        let didClear = await clearTask.value
        XCTAssertTrue(didClear)
        let finalCount = try await database.quoteBarCount()
        XCTAssertEqual(finalCount, 0)
        await store.stop()
    }

    func testShutdownClosesAdmissionBeforeDrainingEveryOperationAndRejectsPostCloseWork()
        async throws
    {
        let database = try MarketDatabase.inMemory()
        let first = Instrument(symbol: "RACEA", name: "竞态甲", namespace: .unitedStates)
        let second = Instrument(symbol: "RACEB", name: "竞态乙", namespace: .unitedStates)
        let added = Instrument(symbol: "RACEC", name: "竞态丙", namespace: .unitedStates)
        try await database.replaceWatchlist(with: [first, second])
        let client = OneShotSuspendingMarketDataClient()
        let closeProbe = DatabaseCloseProbe()
        let store = MonitorStore(
            client: client,
            database: database,
            preferences: makePreferences(),
            databaseClose: { try await closeProbe.close($0) }
        )
        try await store.start()
        await store.refreshAll()
        let gate = MonitorOperationAdmissionGate()
        store.operationAdmissionObserverForTesting = { operation in
            await gate.hold(operation)
        }
        let json = String(
            data: try JSONEncoder().encode([first, second]),
            encoding: .utf8
        )!

        let addTask = Task { @MainActor in await store.add(added) }
        let removeTask = Task { @MainActor in await store.remove(first) }
        let moveTask = Task { @MainActor in
            await store.moveInstruments(from: IndexSet(integer: 0), to: 2)
        }
        let importTask = Task { @MainActor in await store.importWatchlist(fromJSON: json) }
        let clearTask = Task { @MainActor in await store.clearQuoteHistory() }
        let countTask = Task { @MainActor in await store.refreshQuoteBarCount() }
        let refreshTask = Task { @MainActor in await store.refreshAll() }
        try await waitUntil("所有卸载竞态操作获得准入") {
            await gate.heldOperationCount == 7
        }

        let shutdownTask = Task { @MainActor in await store.shutdown() }
        try await waitUntil("停机先关闭操作准入") {
            !store.acceptsOperationsForTesting
        }
        let closeCountBeforeRelease = await closeProbe.closeCount
        XCTAssertEqual(closeCountBeforeRelease, 0)

        await gate.releaseAll()
        _ = await addTask.value
        _ = await removeTask.value
        _ = await moveTask.value
        _ = await importTask.value
        _ = await clearTask.value
        _ = await countTask.value
        _ = await refreshTask.value
        let shutdownFailure = await shutdownTask.value
        XCTAssertNil(shutdownFailure)
        let closeCountAfterShutdown = await closeProbe.closeCount
        XCTAssertEqual(closeCountAfterShutdown, 1)

        let fetchCountAfterClose = await client.fetchCount
        let searchCountAfterClose = await client.searchCount
        do {
            try await store.start()
            XCTFail("Starting after shutdown should be rejected")
        } catch {
            XCTAssertEqual(error as? MonitorStoreOperationError, .unavailable)
        }
        do {
            _ = try await store.search("AAPL")
            XCTFail("Searching after shutdown should be rejected")
        } catch {
            XCTAssertEqual(error as? MonitorStoreOperationError, .unavailable)
        }
        let addResult = await store.add(added)
        XCTAssertEqual(addResult, MonitorStoreOperationError.unavailable.localizedDescription)
        let removeResult = await store.remove(first)
        XCTAssertFalse(removeResult)
        let moveResult = await store.moveInstruments(from: IndexSet(integer: 0), to: 1)
        XCTAssertFalse(moveResult)
        let importResult = await store.importWatchlist(fromJSON: json)
        XCTAssertEqual(
            importResult,
            .failure(MonitorStoreOperationError.unavailable.localizedDescription)
        )
        let clearHistoryResult = await store.clearQuoteHistory()
        XCTAssertFalse(clearHistoryResult)
        let refreshCountResult = await store.refreshQuoteBarCount()
        XCTAssertFalse(refreshCountResult)
        let refreshResult = await store.refreshAll()
        XCTAssertFalse(refreshResult)
        let generatedTargetCount = await store.generatePriceTargetsFromCurrentQuotes()
        XCTAssertNil(generatedTargetCount)
        let flushResult = await store.flushPendingPersistence()
        XCTAssertEqual(
            flushResult,
            MonitorStoreOperationError.unavailable.localizedDescription
        )
        var changedConfiguration = store.alertConfiguration
        changedConfiguration.isEnabled.toggle()
        XCTAssertFalse(store.updateAlertConfiguration(changedConfiguration))
        XCTAssertFalse(
            store.updatePriceTargets(for: first, risingPrice: 100, fallingPrice: 90)
        )
        XCTAssertFalse(store.setPriceTargetsEnabled(for: first, enabled: false))
        let fetchCountAfterRejectedWork = await client.fetchCount
        let searchCountAfterRejectedWork = await client.searchCount
        let finalCloseCount = await closeProbe.closeCount
        XCTAssertEqual(fetchCountAfterRejectedWork, fetchCountAfterClose)
        XCTAssertEqual(searchCountAfterRejectedWork, searchCountAfterClose)
        XCTAssertEqual(finalCloseCount, 1)
    }

    func testShutdownFlushesPendingAlertSettingsBeforeClosingDatabase() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("StockWatchShutdownTests.\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent(MarketDatabase.defaultFileName).path
        let instrument = Instrument.initialWatchlist[2]
        let database = try MarketDatabase.open(atPath: path)
        try await database.replaceWatchlist(with: [instrument])
        let store = MonitorStore(
            client: FailingMarketDataClient(),
            database: database,
            preferences: makePreferences()
        )
        try await store.start()
        let configuration = AlertConfiguration(
            isEnabled: true,
            basis: .targetPrice,
            risingThreshold: 4,
            fallingThreshold: 2
        )
        store.updateAlertConfiguration(configuration)
        store.updatePriceTargets(for: instrument, risingPrice: 220, fallingPrice: 190)

        await store.shutdown()

        let reopened = try MarketDatabase.open(atPath: path)
        let settings = try await reopened.loadAlertSettings()
        XCTAssertEqual(
            settings,
            AlertSettingsSnapshot(
                configuration: configuration,
                priceTargets: [
                    instrument.id: PriceAlertTargets(risingPrice: 220, fallingPrice: 190)
                ]
            )
        )
        try await reopened.close()
    }

    private func waitUntil(
        _ description: String,
        timeout: Duration = .seconds(1),
        condition: @escaping @MainActor () async -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if await condition() {
                return
            }
            try await clock.sleep(for: .milliseconds(1))
        }
        XCTFail("Timed out waiting for \(description)")
        throw MonitorStoreTestWaitError.timedOut(description)
    }

    private func makePreferences() -> StockWatchPreferences {
        let suiteName = "StockWatchTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return StockWatchPreferences(defaults: defaults)
    }

    private func prepareDatabase(
        atPath path: String,
        watchlist: [Instrument]
    ) async throws {
        let database = try MarketDatabase.open(atPath: path)
        try await database.replaceWatchlist(with: watchlist)
        try await database.close()
    }

    private func makeQuote(
        for instrument: Instrument,
        price: Double,
        at suppliedTime: Date? = nil
    ) -> QuoteSnapshot {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = instrument.market.timeZone
        let time =
            suppliedTime
            ?? calendar.date(
                bySettingHour: 12,
                minute: 0,
                second: 0,
                of: Date()
            )!
        return QuoteSnapshot(
            instrumentID: instrument.id,
            minuteBars: [
                MinuteBar(
                    time: time,
                    open: price - 1,
                    close: price,
                    high: price + 1,
                    low: price - 2
                ),
                MinuteBar(
                    time: time.addingTimeInterval(60),
                    open: price,
                    close: price,
                    high: price + 1,
                    low: price - 1
                ),
            ],
            dayOpen: price - 1,
            previousClose: price - 2,
            lastPrice: price,
            marketTime: time.addingTimeInterval(60),
            receivedAt: time.addingTimeInterval(61),
            source: .tencent
        )
    }
}

private enum MonitorStoreTestWaitError: Error {
    case timedOut(String)
}

@MainActor
private final class AlertDismissalTimingProbe {
    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Void, Error>
    }

    private(set) var now = ContinuousClock().now
    private(set) var requestedSleeps: [Duration] = []
    private var waiters: [Waiter] = []

    func advance(by duration: Duration) {
        now = now.advanced(by: duration)
    }

    func sleep(for duration: Duration) async throws {
        let id = UUID()
        requestedSleeps.append(duration)
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Void, Error>) in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                } else {
                    waiters.append(Waiter(id: id, continuation: continuation))
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.cancelSleep(id: id)
            }
        }
    }

    func completeLatestSleep() {
        guard let waiter = waiters.popLast() else { return }
        waiter.continuation.resume()
    }

    private func cancelSleep(id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        let waiter = waiters.remove(at: index)
        waiter.continuation.resume(throwing: CancellationError())
    }
}

private struct FailingMarketDataClient: MarketDataClient {
    func searchInstruments(matching query: String) async throws -> [Instrument] {
        []
    }

    func fetchQuote(for instrument: Instrument) async throws -> QuoteSnapshot {
        throw URLError(.notConnectedToInternet)
    }
}

private struct NoIntradayDataMarketDataClient: MarketDataClient {
    func searchInstruments(matching query: String) async throws -> [Instrument] {
        []
    }

    func fetchQuote(for instrument: Instrument) async throws -> QuoteSnapshot {
        throw MarketDataError.noIntradayData
    }
}

private struct StaticMarketDataClient: MarketDataClient {
    let quote: QuoteSnapshot

    func searchInstruments(matching query: String) async throws -> [Instrument] {
        []
    }

    func fetchQuote(for instrument: Instrument) async throws -> QuoteSnapshot {
        quote
    }
}

private struct PerInstrumentMarketDataClient: MarketDataClient {
    let quotes: [InstrumentID: QuoteSnapshot]

    func searchInstruments(matching query: String) async throws -> [Instrument] {
        []
    }

    func fetchQuote(for instrument: Instrument) async throws -> QuoteSnapshot {
        guard let quote = quotes[instrument.id] else {
            throw MarketDataError.invalidResponse
        }
        return quote
    }
}

private actor AlertSettingsPersistenceProbe {
    private let blockingCommittedSnapshot: AlertSettingsSnapshot
    private var events: [AlertSettingsPersistenceEvent] = []
    private var eventWaiter: CheckedContinuation<AlertSettingsPersistenceEvent, Never>?
    private var blockedCommitContinuation: CheckedContinuation<Void, Never>?
    private var hasBlockedCommit = false
    private var releaseRequested = false

    init(blockingCommittedSnapshot: AlertSettingsSnapshot) {
        self.blockingCommittedSnapshot = blockingCommittedSnapshot
    }

    func receive(_ event: AlertSettingsPersistenceEvent) async {
        if let eventWaiter {
            self.eventWaiter = nil
            eventWaiter.resume(returning: event)
        } else {
            events.append(event)
        }

        guard case .committed(let snapshot, _) = event,
            snapshot == blockingCommittedSnapshot,
            !hasBlockedCommit
        else {
            return
        }
        hasBlockedCommit = true
        guard !releaseRequested else { return }
        await withCheckedContinuation { continuation in
            blockedCommitContinuation = continuation
        }
    }

    func nextEvent() async -> AlertSettingsPersistenceEvent {
        if !events.isEmpty {
            return events.removeFirst()
        }
        return await withCheckedContinuation { continuation in
            eventWaiter = continuation
        }
    }

    func releaseBlockedCommit() {
        releaseRequested = true
        guard let blockedCommitContinuation else { return }
        self.blockedCommitContinuation = nil
        blockedCommitContinuation.resume()
    }
}

private actor DatabaseCloseProbe {
    private(set) var closeCount = 0

    func close(_ database: MarketDatabase) async throws {
        closeCount += 1
        try await database.close()
    }
}

private actor MonitorOperationAdmissionGate {
    private var isReleased = false
    private var heldOperations: [MonitorStoreOperation] = []
    private var waiters: [CheckedContinuation<Void, Never>] = []

    var heldOperationCount: Int { heldOperations.count }

    func hold(_ operation: MonitorStoreOperation) async {
        heldOperations.append(operation)
        guard !isReleased else { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func releaseAll() {
        isReleased = true
        let waiters = waiters
        self.waiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }
}

private actor OneShotSuspendingMarketDataClient: MarketDataClient {
    private var nextQuote: QuoteSnapshot?
    private(set) var fetchCount = 0
    private(set) var searchCount = 0
    private var suspendedFetch:
        (
            quote: QuoteSnapshot,
            continuation: CheckedContinuation<QuoteSnapshot, Error>
        )?

    func searchInstruments(matching query: String) async throws -> [Instrument] {
        searchCount += 1
        return []
    }

    func fetchQuote(for instrument: Instrument) async throws -> QuoteSnapshot {
        fetchCount += 1
        guard let quote = nextQuote, quote.instrumentID == instrument.id else {
            throw URLError(.notConnectedToInternet)
        }
        nextQuote = nil
        return try await withCheckedThrowingContinuation { continuation in
            suspendedFetch = (quote, continuation)
        }
    }

    func suspendNextFetch(with quote: QuoteSnapshot) {
        nextQuote = quote
    }

    var isFetchSuspended: Bool {
        suspendedFetch != nil
    }

    func resumeSuspendedFetch() {
        guard let suspendedFetch else { return }
        self.suspendedFetch = nil
        suspendedFetch.continuation.resume(returning: suspendedFetch.quote)
    }
}

private actor CountingMarketDataClient: MarketDataClient {
    private var suspendsRequests = false
    private var activeRequests = 0
    private var maximumActiveRequests = 0
    private var requestCount = 0
    private var requestsAreReleased = false
    private var requestWaiters: [CheckedContinuation<Void, Never>] = []

    func searchInstruments(matching query: String) async throws -> [Instrument] {
        []
    }

    func fetchQuote(for instrument: Instrument) async throws -> QuoteSnapshot {
        activeRequests += 1
        requestCount += 1
        maximumActiveRequests = max(maximumActiveRequests, activeRequests)
        defer { activeRequests -= 1 }
        if suspendsRequests, !requestsAreReleased {
            await withCheckedContinuation { continuation in
                requestWaiters.append(continuation)
            }
        }
        let time = Date(timeIntervalSince1970: 1_700_000_000)
        return QuoteSnapshot(
            instrumentID: instrument.id,
            minuteBars: [
                MinuteBar(time: time, open: 99, close: 100, high: 101, low: 98),
                MinuteBar(
                    time: time.addingTimeInterval(60),
                    open: 100,
                    close: 101,
                    high: 102,
                    low: 99
                ),
            ],
            dayOpen: 99,
            previousClose: 98,
            lastPrice: 101,
            marketTime: time.addingTimeInterval(60),
            receivedAt: time.addingTimeInterval(61),
            source: .tencent
        )
    }

    func resetMetrics() {
        activeRequests = 0
        maximumActiveRequests = 0
        requestCount = 0
    }

    func suspendRequests() {
        suspendsRequests = true
        requestsAreReleased = false
    }

    func resumeRequests() {
        requestsAreReleased = true
        let waiters = requestWaiters
        requestWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }

    func metrics() -> (requestCount: Int, maximumActiveRequests: Int) {
        (requestCount, maximumActiveRequests)
    }
}
