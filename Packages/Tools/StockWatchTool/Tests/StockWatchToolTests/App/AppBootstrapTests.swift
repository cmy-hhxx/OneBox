import Foundation
import GRDB
import XCTest

@testable import StockWatchTool

@MainActor
final class StockWatchBootstrapTests: XCTestCase {
    func testConstructionIsLazyAndFailedOpenCanRetryWithoutMemoryFallback() async throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let databasePath = temporaryDirectory.appendingPathComponent("marketsprite.sqlite").path
        let factory = RetryingDatabaseFactory(databasePath: databasePath)
        let preferences = PreferencesFactoryProbe()
        let bootstrap = StockWatchBootstrap(
            preferencesFactory: { preferences.make() },
            client: FailingMarketDataClient(),
            databasePath: databasePath,
            databaseFactory: { try await factory.open() }
        )

        let attemptsBeforeStart = await factory.attemptCount
        XCTAssertEqual(attemptsBeforeStart, 0)
        XCTAssertEqual(preferences.creationCount, 0)
        XCTAssertNil(bootstrap.store)
        XCTAssertNil(bootstrap.preferences)

        await bootstrap.start()

        let attemptsAfterFailure = await factory.attemptCount
        XCTAssertEqual(attemptsAfterFailure, 1)
        XCTAssertEqual(preferences.creationCount, 0)
        XCTAssertNil(bootstrap.store)
        XCTAssertNil(bootstrap.preferences)
        XCTAssertEqual(bootstrap.failure?.databasePath, databasePath)
        XCTAssertNotNil(bootstrap.failure?.message)
        XCTAssertFalse(bootstrap.failure?.canClearQuoteCache == true)

        await bootstrap.start(retryingShutdownFailure: true)

        let attemptsAfterRetry = await factory.attemptCount
        XCTAssertEqual(attemptsAfterRetry, 2)
        XCTAssertEqual(preferences.creationCount, 1)
        XCTAssertEqual(bootstrap.store?.databasePath, databasePath)
        XCTAssertNotNil(bootstrap.preferences)
        XCTAssertNil(bootstrap.failure)
        await bootstrap.shutdown()
    }

    func testStartupFailureMessageDoesNotExposeLegacyPathOrWatchlistContent() async {
        let legacyPath = "/Users/private/MarketSprite/marketsprite.sqlite"
        let bootstrap = StockWatchBootstrap(
            preferencesFactory: { self.makePreferences() },
            client: FailingMarketDataClient(),
            databasePath: "/Users/private/OneBox/StockWatch/marketsprite.sqlite",
            databaseFactory: {
                throw StockWatchStorageError.legacyImportFailed(
                    path: legacyPath,
                    reason: "invalid target for us:PRIVATE and \(legacyPath)"
                )
            }
        )

        await bootstrap.start()

        XCTAssertEqual(bootstrap.failure?.databasePath, legacyPath)
        XCTAssertEqual(
            bootstrap.failure?.message,
            "无法安全导入独立 MarketSprite 数据库。请检查旧应用已完全退出且数据库有效。"
        )
        XCTAssertFalse(bootstrap.failure?.message.contains("PRIVATE") == true)
        XCTAssertFalse(bootstrap.failure?.message.contains("/Users/") == true)
        XCTAssertFalse(bootstrap.failure?.canClearQuoteCache == true)
    }

    func testQuoteCacheRecoveryIsOwnedByVisibleLifecycleAndCancelledOnExit() async throws {
        let clearProbe = QuoteCacheClearProbe()
        let bootstrap = StockWatchBootstrap(
            preferencesFactory: { self.makePreferences() },
            client: FailingMarketDataClient(),
            databasePath: "/tmp/quote-cache-recovery.sqlite",
            databaseFactory: {
                throw StockWatchStartupError.quoteCacheUnavailable
            },
            quoteCacheClear: {
                try await clearProbe.clear()
            }
        )
        let runTask = Task { @MainActor in
            await bootstrap.run()
        }
        try await waitForFailure(in: bootstrap)
        XCTAssertTrue(bootstrap.failure?.canClearQuoteCache == true)

        bootstrap.requestQuoteCacheClear()
        try await clearProbe.waitUntilStarted()
        XCTAssertTrue(bootstrap.isClearingQuoteCache)

        runTask.cancel()
        await runTask.value

        let wasCancelled = await clearProbe.wasCancelled
        XCTAssertTrue(wasCancelled)
        XCTAssertFalse(bootstrap.isClearingQuoteCache)
    }

    func testNonContiguousStoredPositionsAreNormalizedDuringOpen() async throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let databasePath =
            temporaryDirectory
            .appendingPathComponent("invalid-restore.sqlite")
            .path
        try await prepareInvalidRestoreDatabase(atPath: databasePath)
        let bootstrap = StockWatchBootstrap(
            preferencesFactory: { self.makePreferences() },
            client: FailingMarketDataClient(),
            databasePath: databasePath,
            databaseFactory: { try MarketDatabase.open(atPath: databasePath) }
        )

        await bootstrap.start()

        XCTAssertNotNil(bootstrap.store)
        XCTAssertNil(bootstrap.failure)
        await bootstrap.shutdown()
        let positions = try SQLiteTestSupport.execute(
            "SELECT group_concat(position, ',') FROM watchlist ORDER BY position;",
            atPath: databasePath
        )
        XCTAssertEqual(positions.trimmingCharacters(in: .whitespacesAndNewlines), "0")
    }

    func testFailedFirstCanonicalOpenRemovesPartialDatabaseFiles() async throws {
        let applicationSupport = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: applicationSupport) }
        let storage = StockWatchStorage(
            applicationSupportDirectory: applicationSupport,
            databaseOpenerForTesting: { databaseURL in
                try Data("partial sqlite".utf8).write(to: databaseURL)
                throw TestError.databaseUnavailable
            }
        )

        do {
            _ = try await storage.open()
            XCTFail("Expected the injected canonical open to fail")
        } catch TestError.databaseUnavailable {
            // Expected.
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: storage.databasePath))
        XCTAssertFalse(FileManager.default.fileExists(atPath: storage.databasePath + "-wal"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: storage.databasePath + "-shm"))
    }

    func testQuoteCacheRecoveryPreservesWatchlistAndAlerts() async throws {
        let applicationSupport = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: applicationSupport) }
        let storage = StockWatchStorage(applicationSupportDirectory: applicationSupport)
        let database = try await storage.open()
        let instrument = Instrument.initialWatchlist[0]
        let settings = AlertSettingsSnapshot(
            configuration: AlertConfiguration(
                isEnabled: false,
                basis: .percentage,
                risingThreshold: 4,
                fallingThreshold: 5
            ),
            priceTargets: [:]
        )
        try await database.replaceWatchlist(with: [instrument])
        try await database.saveAlertSettings(settings)
        try await database.saveQuote(
            QuoteSnapshot(
                instrumentID: instrument.id,
                minuteBars: [],
                dayOpen: 1_500,
                previousClose: 1_490,
                lastPrice: 1_510,
                marketTime: try XCTUnwrap(
                    ISO8601DateFormatter().date(from: "2026-07-30T07:00:00Z")
                ),
                receivedAt: try XCTUnwrap(
                    ISO8601DateFormatter().date(from: "2026-07-30T07:00:01Z")
                ),
                source: .tencent
            ),
            for: instrument
        )
        try await database.close()

        try await storage.clearQuoteCache()

        let reopened = try await storage.open()
        let restoredWatchlist = try await reopened.loadWatchlist()
        let restoredSettings = try await reopened.loadAlertSettings()
        let restoredQuotes = try await reopened.loadLatestQuotes(for: [instrument])
        XCTAssertEqual(restoredWatchlist, [instrument])
        XCTAssertEqual(restoredSettings, settings)
        XCTAssertTrue(restoredQuotes.isEmpty)
        try await reopened.close()
    }

    func testCancellingViewLifetimeFlushesAndClosesStore() async throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let databasePath = temporaryDirectory.appendingPathComponent("marketsprite.sqlite").path
        let bootstrap = StockWatchBootstrap(
            preferencesFactory: { self.makePreferences() },
            client: FailingMarketDataClient(),
            databasePath: databasePath,
            databaseFactory: { try MarketDatabase.open(atPath: databasePath) }
        )
        let runTask = Task { @MainActor in
            await bootstrap.run()
        }
        defer { runTask.cancel() }
        let store = try await waitForStore(in: bootstrap)
        let updatedConfiguration = AlertConfiguration(
            isEnabled: false,
            basis: .percentage,
            risingThreshold: 4,
            fallingThreshold: 5
        )
        store.updateAlertConfiguration(updatedConfiguration)

        runTask.cancel()
        await runTask.value

        XCTAssertNil(bootstrap.store)
        let reopened = try MarketDatabase.open(atPath: databasePath)
        let persisted = try await reopened.loadAlertSettings()
        XCTAssertEqual(persisted.configuration, updatedConfiguration)
        try await reopened.close()
    }

    func testApplicationTerminationFlushesAndClosesVisibleStoreOnlyOnce() async throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let databasePath = temporaryDirectory.appendingPathComponent("marketsprite.sqlite").path
        let session = StockWatchModuleSession()
        let databaseClose = CountingDatabaseClose()
        let bootstrap = StockWatchBootstrap(
            lifecycleCoordinator: session.lifecycleCoordinator,
            preferencesFactory: { self.makePreferences() },
            client: FailingMarketDataClient(),
            databasePath: databasePath,
            databaseFactory: { try MarketDatabase.open(atPath: databasePath) },
            databaseClose: { try await databaseClose.close($0) }
        )
        let visibleRun = Task { @MainActor in
            await session.runVisibleLifecycle {
                await bootstrap.run()
            }
        }
        let store = try await waitForStore(in: bootstrap)
        let updatedConfiguration = AlertConfiguration(
            isEnabled: false,
            basis: .percentage,
            risingThreshold: 6,
            fallingThreshold: 7
        )
        store.updateAlertConfiguration(updatedConfiguration)

        await session.prepareForApplicationTermination()
        await session.prepareForApplicationTermination()
        await visibleRun.value

        XCTAssertNil(bootstrap.store)
        let closeCount = await databaseClose.closeCount
        XCTAssertEqual(closeCount, 1)
        let reopened = try MarketDatabase.open(atPath: databasePath)
        let persisted = try await reopened.loadAlertSettings()
        XCTAssertEqual(persisted.configuration, updatedConfiguration)
        try await reopened.close()
    }

    func testApplicationTerminationCancelsSuspendedStartupAndClosesOpenedDatabase() async throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let databasePath = temporaryDirectory.appendingPathComponent("marketsprite.sqlite").path
        let session = StockWatchModuleSession()
        let databaseFactory = SuspendingRetryDatabaseFactory(databasePath: databasePath)
        let databaseClose = CountingDatabaseClose()
        let bootstrap = StockWatchBootstrap(
            lifecycleCoordinator: session.lifecycleCoordinator,
            preferencesFactory: { self.makePreferences() },
            client: FailingMarketDataClient(),
            databasePath: databasePath,
            databaseFactory: { try await databaseFactory.open() },
            databaseClose: { try await databaseClose.close($0) }
        )
        let visibleRun = Task { @MainActor in
            await session.runVisibleLifecycle {
                await bootstrap.run()
            }
        }
        try await waitForFailure(in: bootstrap)
        bootstrap.requestRetry()
        try await databaseFactory.waitUntilRetryOpenIsSuspended()

        let terminationTask = Task { @MainActor in
            await session.prepareForApplicationTermination()
        }
        for _ in 0..<10 {
            await Task.yield()
        }
        await databaseFactory.resumeRetryOpen()
        await terminationTask.value
        await visibleRun.value

        XCTAssertNil(bootstrap.store)
        XCTAssertNil(bootstrap.preferences)
        let closeCount = await databaseClose.closeCount
        XCTAssertEqual(closeCount, 1)
        let reopened = try MarketDatabase.open(atPath: databasePath)
        try await reopened.close()
    }

    func testRapidRemountWaitsForPriorDatabaseCloseBeforeOpening() async throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let databasePath = temporaryDirectory.appendingPathComponent("marketsprite.sqlite").path
        let lifecycleCoordinator = StockWatchLifecycleCoordinator()
        let databaseFactory = CountingDatabaseFactory(databasePath: databasePath)
        let closeGate = SuspendingDatabaseClose()
        let first = StockWatchBootstrap(
            lifecycleCoordinator: lifecycleCoordinator,
            preferencesFactory: { self.makePreferences() },
            client: FailingMarketDataClient(),
            databasePath: databasePath,
            databaseFactory: { try await databaseFactory.open() },
            databaseClose: { try await closeGate.close($0) }
        )
        await first.start()
        XCTAssertNotNil(first.store)

        let firstShutdown = Task { @MainActor in
            await first.shutdown()
        }
        try await closeGate.waitUntilCloseIsSuspended()

        let secondPreferences = PreferencesFactoryProbe()
        let second = StockWatchBootstrap(
            lifecycleCoordinator: lifecycleCoordinator,
            preferencesFactory: { secondPreferences.make() },
            client: FailingMarketDataClient(),
            databasePath: databasePath,
            databaseFactory: { try await databaseFactory.open() }
        )
        let secondStart = Task { @MainActor in
            await second.start()
        }
        for _ in 0..<100 {
            await Task.yield()
        }
        let attemptsWhileClosing = await databaseFactory.attemptCount
        XCTAssertEqual(attemptsWhileClosing, 1)
        XCTAssertEqual(secondPreferences.creationCount, 0)
        XCTAssertNil(second.store)

        await closeGate.resumeClose()
        _ = await firstShutdown.value
        await secondStart.value

        let attemptsAfterClose = await databaseFactory.attemptCount
        XCTAssertEqual(attemptsAfterClose, 2)
        XCTAssertEqual(secondPreferences.creationCount, 1)
        XCTAssertNotNil(second.store)
        await second.shutdown()
    }

    func testCancellingSuspendedRetryClosesOpenedDatabaseWithoutPublishingStore() async throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let databasePath = temporaryDirectory.appendingPathComponent("marketsprite.sqlite").path
        let databaseFactory = SuspendingRetryDatabaseFactory(databasePath: databasePath)
        let databaseClose = CountingDatabaseClose()
        let preferences = PreferencesFactoryProbe()
        let bootstrap = StockWatchBootstrap(
            preferencesFactory: { preferences.make() },
            client: FailingMarketDataClient(),
            databasePath: databasePath,
            databaseFactory: { try await databaseFactory.open() },
            databaseClose: { try await databaseClose.close($0) }
        )
        let runTask = Task { @MainActor in
            await bootstrap.run()
        }
        try await waitForFailure(in: bootstrap)

        bootstrap.requestRetry()
        try await databaseFactory.waitUntilRetryOpenIsSuspended()
        runTask.cancel()
        await databaseFactory.resumeRetryOpen()
        await runTask.value

        XCTAssertNil(bootstrap.store)
        XCTAssertNil(bootstrap.preferences)
        XCTAssertEqual(preferences.creationCount, 0)
        let closeCount = await databaseClose.closeCount
        XCTAssertEqual(closeCount, 1)

        let reopened = try MarketDatabase.open(atPath: databasePath)
        try await reopened.close()
    }

    func testShutdownFailureIsTypedAndSurfacedBeforeNextMountCanOpen() async throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let databasePath = temporaryDirectory.appendingPathComponent("marketsprite.sqlite").path
        let lifecycleCoordinator = StockWatchLifecycleCoordinator()
        let databaseFactory = CountingDatabaseFactory(databasePath: databasePath)
        let databaseClose = FailFirstDatabaseClose()
        let first = StockWatchBootstrap(
            lifecycleCoordinator: lifecycleCoordinator,
            preferencesFactory: { self.makePreferences() },
            client: FailingMarketDataClient(),
            databasePath: databasePath,
            databaseFactory: { try await databaseFactory.open() },
            databaseClose: { try await databaseClose.close($0) }
        )
        await first.start()

        let shutdownFailure = await first.shutdown()

        XCTAssertNotNil(shutdownFailure?.databaseCloseMessage)
        let second = StockWatchBootstrap(
            lifecycleCoordinator: lifecycleCoordinator,
            preferencesFactory: { self.makePreferences() },
            client: FailingMarketDataClient(),
            databasePath: databasePath,
            databaseFactory: { try await databaseFactory.open() }
        )
        await second.start()

        let attemptsBeforeRecovery = await databaseFactory.attemptCount
        XCTAssertEqual(attemptsBeforeRecovery, 1)
        XCTAssertNil(second.store)
        XCTAssertEqual(second.failure?.shutdownFailure, shutdownFailure)

        await second.start(retryingShutdownFailure: true)

        let attemptsAfterRecovery = await databaseFactory.attemptCount
        XCTAssertEqual(attemptsAfterRecovery, 2)
        XCTAssertNotNil(second.store)
        XCTAssertNil(second.failure)
        await second.shutdown()
    }

    func testDefaultStoragePathUsesOneBoxStockWatchNamespace() {
        let fileManager = FileManager.default
        let expected = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first?
        .appendingPathComponent("OneBox", isDirectory: true)
        .appendingPathComponent("StockWatch", isDirectory: true)
        .appendingPathComponent("marketsprite.sqlite", isDirectory: false)
        .path

        XCTAssertEqual(StockWatchStorage(fileManager: fileManager).databasePath, expected)
    }

    func testValidStandaloneDatabaseIsImportedOnceWithoutModification() async throws {
        let applicationSupport = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: applicationSupport) }
        let legacyDirectory = applicationSupport.appendingPathComponent(
            "MarketSprite",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: legacyDirectory,
            withIntermediateDirectories: true
        )
        let legacyURL = legacyDirectory.appendingPathComponent("marketsprite.sqlite")
        let originalWatchlist = Array(Instrument.initialWatchlist.prefix(2))
        let legacyDatabase = try MarketDatabase.open(atPath: legacyURL.path)
        try await legacyDatabase.replaceWatchlist(with: originalWatchlist)
        try await legacyDatabase.close()
        try SQLiteTestSupport.execute(
            "UPDATE watchlist SET position = 3 WHERE instrument_id = "
                + "'\(originalWatchlist[1].id.rawValue)';",
            atPath: legacyURL.path
        )
        let legacyBytesBeforeImport = try Data(contentsOf: legacyURL)
        let storage = StockWatchStorage(applicationSupportDirectory: applicationSupport)

        let importedDatabase = try await storage.open()
        let importedWatchlist = try await importedDatabase.loadWatchlist()
        try await importedDatabase.close()
        let legacyBytesAfterImport = try Data(contentsOf: legacyURL)
        XCTAssertEqual(importedWatchlist, originalWatchlist)
        XCTAssertEqual(legacyBytesAfterImport, legacyBytesBeforeImport)

        let changedLegacyDatabase = try MarketDatabase.open(atPath: legacyURL.path)
        try await changedLegacyDatabase.replaceWatchlist(with: [Instrument.initialWatchlist[2]])
        try await changedLegacyDatabase.close()

        let reopenedDatabase = try await storage.open()
        let reopenedWatchlist = try await reopenedDatabase.loadWatchlist()
        try await reopenedDatabase.close()
        XCTAssertEqual(reopenedWatchlist, originalWatchlist)
    }

    func testStandaloneImportRejectsNonFinitePriceTargetWithoutArtifacts() async throws {
        let applicationSupport = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: applicationSupport) }
        let legacyDirectory = applicationSupport.appendingPathComponent(
            "MarketSprite",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: legacyDirectory,
            withIntermediateDirectories: true
        )
        let legacyURL = legacyDirectory.appendingPathComponent("marketsprite.sqlite")
        let instrument = Instrument.initialWatchlist[2]
        let legacyDatabase = try MarketDatabase.open(atPath: legacyURL.path)
        try await legacyDatabase.replaceWatchlist(with: [instrument])
        try await legacyDatabase.saveAlertSettings(
            AlertSettingsSnapshot(
                configuration: .default,
                priceTargets: [
                    instrument.id: PriceAlertTargets(risingPrice: 220, fallingPrice: nil)
                ]
            )
        )
        try await legacyDatabase.close()
        try SQLiteTestSupport.execute(
            "UPDATE price_alerts SET rising_price = 1e999;",
            atPath: legacyURL.path
        )
        let legacyBytes = try Data(contentsOf: legacyURL)
        let storage = StockWatchStorage(applicationSupportDirectory: applicationSupport)

        do {
            _ = try await storage.open()
            XCTFail("Non-finite source target should fail import")
        } catch let error as StockWatchStorageError {
            XCTAssertEqual(error.recoveryDatabasePath, legacyURL.path)
            XCTAssertTrue(error.localizedDescription.contains("目标价"))
        }

        XCTAssertEqual(try Data(contentsOf: legacyURL), legacyBytes)
        XCTAssertFalse(FileManager.default.fileExists(atPath: storage.databasePath))
        try assertNoImportArtifacts(in: applicationSupport)
    }

    func testLiveWALSourceIsRejectedWithoutTouchingDatabaseOrSidecars() async throws {
        let applicationSupport = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: applicationSupport) }
        let legacyDirectory = applicationSupport.appendingPathComponent(
            "MarketSprite",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: legacyDirectory,
            withIntermediateDirectories: true
        )
        let legacyURL = legacyDirectory.appendingPathComponent("marketsprite.sqlite")
        let initial = try MarketDatabase.open(atPath: legacyURL.path)
        try await initial.close()

        let liveWriter = try DatabaseQueue(path: legacyURL.path)
        defer { try? liveWriter.close() }
        try await liveWriter.writeWithoutTransaction { database in
            try database.execute(sql: "PRAGMA journal_mode = WAL")
            try database.execute(sql: "PRAGMA wal_autocheckpoint = 0")
            try database.execute(
                sql: "UPDATE watchlist SET name = 'WAL测试' WHERE instrument_id = ?",
                arguments: [Instrument.initialWatchlist[0].id.rawValue]
            )
        }
        let trackedURLs = [
            legacyURL,
            URL(fileURLWithPath: legacyURL.path + "-wal"),
            URL(fileURLWithPath: legacyURL.path + "-shm"),
        ]
        for url in trackedURLs {
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), url.path)
        }
        let bytesBeforeImport = try Dictionary(
            uniqueKeysWithValues: trackedURLs.map { ($0.path, try Data(contentsOf: $0)) }
        )
        let storage = StockWatchStorage(applicationSupportDirectory: applicationSupport)

        do {
            _ = try await storage.open()
            XCTFail("A live WAL source should not be opened")
        } catch let error as StockWatchStorageError {
            XCTAssertEqual(error.recoveryDatabasePath, legacyURL.path)
            XCTAssertTrue(error.localizedDescription.contains("checkpoint"))
            XCTAssertTrue(error.localizedDescription.contains("完全退出 MarketSprite"))
        }

        for url in trackedURLs {
            XCTAssertEqual(try Data(contentsOf: url), bytesBeforeImport[url.path])
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: storage.databasePath))
        try assertNoImportArtifacts(in: applicationSupport)
    }

    func testPreCancelledImportLeavesNoCanonicalOrImportArtifact() async throws {
        let applicationSupport = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: applicationSupport) }
        let legacyDirectory = applicationSupport.appendingPathComponent(
            "MarketSprite",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: legacyDirectory,
            withIntermediateDirectories: true
        )
        let legacyURL = legacyDirectory.appendingPathComponent("marketsprite.sqlite")
        let legacyDatabase = try MarketDatabase.open(atPath: legacyURL.path)
        try await legacyDatabase.close()
        let legacyBytes = try Data(contentsOf: legacyURL)
        let storage = StockWatchStorage(applicationSupportDirectory: applicationSupport)
        let task = Task { try await storage.open() }
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("A cancelled import should not open a database")
        } catch is CancellationError {
            // Expected.
        }

        XCTAssertEqual(try Data(contentsOf: legacyURL), legacyBytes)
        XCTAssertFalse(FileManager.default.fileExists(atPath: storage.databasePath))
        let targetDirectory =
            applicationSupport
            .appendingPathComponent("OneBox", isDirectory: true)
            .appendingPathComponent("StockWatch", isDirectory: true)
        if FileManager.default.fileExists(atPath: targetDirectory.path) {
            let remainingNames = try FileManager.default.contentsOfDirectory(
                atPath: targetDirectory.path
            )
            XCTAssertFalse(remainingNames.contains { $0.contains(".importing-") })
        }
    }

    func testCancellationAfterSnapshotCopyRemovesTemporaryAndCanonicalFiles() async throws {
        let applicationSupport = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: applicationSupport) }
        let legacyDirectory = applicationSupport.appendingPathComponent(
            "MarketSprite",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: legacyDirectory,
            withIntermediateDirectories: true
        )
        let legacyURL = legacyDirectory.appendingPathComponent("marketsprite.sqlite")
        let legacyDatabase = try MarketDatabase.open(atPath: legacyURL.path)
        try await legacyDatabase.close()
        let legacyBytes = try Data(contentsOf: legacyURL)
        let importGate = ImportStageGate()
        let storage = StockWatchStorage(
            applicationSupportDirectory: applicationSupport,
            importStageObserverForTesting: { stage in
                await importGate.observe(stage)
            }
        )
        let task = Task { try await storage.open() }

        try await importGate.waitUntilSnapshotCopied()
        let targetDirectory =
            applicationSupport
            .appendingPathComponent("OneBox", isDirectory: true)
            .appendingPathComponent("StockWatch", isDirectory: true)
        let namesWhileSuspended = try FileManager.default.contentsOfDirectory(
            atPath: targetDirectory.path
        )
        XCTAssertTrue(namesWhileSuspended.contains { $0.contains(".importing-") })

        task.cancel()
        await importGate.resume()
        do {
            _ = try await task.value
            XCTFail("A cancelled import should not open a database")
        } catch is CancellationError {
            // Expected.
        }

        XCTAssertEqual(try Data(contentsOf: legacyURL), legacyBytes)
        XCTAssertFalse(FileManager.default.fileExists(atPath: storage.databasePath))
        try assertNoImportArtifacts(in: applicationSupport)
    }

    func testInvalidStandaloneDatabaseLeavesNoCanonicalOrImportArtifact() async throws {
        let applicationSupport = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: applicationSupport) }
        let legacyDirectory = applicationSupport.appendingPathComponent(
            "MarketSprite",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: legacyDirectory,
            withIntermediateDirectories: true
        )
        let legacyURL = legacyDirectory.appendingPathComponent("marketsprite.sqlite")
        try Data("not a MarketSprite database".utf8).write(to: legacyURL)
        let legacyBytes = try Data(contentsOf: legacyURL)
        let storage = StockWatchStorage(applicationSupportDirectory: applicationSupport)

        do {
            _ = try await storage.open()
            XCTFail("Invalid legacy storage should fail")
        } catch let error as StockWatchStorageError {
            XCTAssertEqual(error.recoveryDatabasePath, legacyURL.path)
            XCTAssertFalse(FileManager.default.fileExists(atPath: storage.databasePath))
        } catch {
            XCTFail("Unexpected storage error: \(error)")
        }

        let legacyBytesAfterFailure = try Data(contentsOf: legacyURL)
        XCTAssertEqual(legacyBytesAfterFailure, legacyBytes)
        let targetDirectory =
            applicationSupport
            .appendingPathComponent("OneBox", isDirectory: true)
            .appendingPathComponent("StockWatch", isDirectory: true)
        let remainingNames = try FileManager.default.contentsOfDirectory(
            atPath: targetDirectory.path)
        XCTAssertFalse(remainingNames.contains { $0.contains(".importing-") })
    }

    func testStandaloneImportRejectsCorruptedQuoteDomainData() async throws {
        for corruptionSQL in [
            "UPDATE quote_cache SET session_date = '2026-07-29';",
            "UPDATE quote_cache SET last_price = 1e999;",
            "UPDATE minute_bars SET open = 1e999, close = 1e999, high = 1e999;",
        ] {
            try await assertStandaloneImportRejectsQuoteCorruption(corruptionSQL)
        }
    }

    private func assertStandaloneImportRejectsQuoteCorruption(
        _ corruptionSQL: String
    ) async throws {
        let applicationSupport = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: applicationSupport) }
        let legacyDirectory = applicationSupport.appendingPathComponent(
            "MarketSprite",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: legacyDirectory,
            withIntermediateDirectories: true
        )
        let legacyURL = legacyDirectory.appendingPathComponent("marketsprite.sqlite")
        let instrument = Instrument.initialWatchlist[2]
        let marketTime = try XCTUnwrap(
            ISO8601DateFormatter().date(from: "2026-07-30T20:00:00Z")
        )
        let legacyDatabase = try MarketDatabase.open(atPath: legacyURL.path)
        try await legacyDatabase.replaceWatchlist(with: [instrument])
        try await legacyDatabase.saveQuote(
            QuoteSnapshot(
                instrumentID: instrument.id,
                minuteBars: [
                    MinuteBar(
                        time: marketTime,
                        open: 209,
                        close: 210,
                        high: 211,
                        low: 208
                    )
                ],
                dayOpen: 209,
                previousClose: 208,
                lastPrice: 210,
                marketTime: marketTime,
                receivedAt: marketTime.addingTimeInterval(1),
                source: .tencent
            ),
            for: instrument
        )
        try await legacyDatabase.close()
        try SQLiteTestSupport.execute(corruptionSQL, atPath: legacyURL.path)
        let legacyBytesBeforeImport = try Data(contentsOf: legacyURL)
        let storage = StockWatchStorage(applicationSupportDirectory: applicationSupport)

        do {
            let importedDatabase = try await storage.open()
            try await importedDatabase.close()
            XCTFail("Corrupted quote data should not import: \(corruptionSQL)")
        } catch let error as StockWatchStorageError {
            XCTAssertEqual(error.recoveryDatabasePath, legacyURL.path)
        } catch {
            XCTFail("Unexpected storage error for \(corruptionSQL): \(error)")
        }

        XCTAssertEqual(try Data(contentsOf: legacyURL), legacyBytesBeforeImport)
        XCTAssertFalse(FileManager.default.fileExists(atPath: storage.databasePath))
        let targetDirectory =
            applicationSupport
            .appendingPathComponent("OneBox", isDirectory: true)
            .appendingPathComponent("StockWatch", isDirectory: true)
        let remainingNames = try FileManager.default.contentsOfDirectory(
            atPath: targetDirectory.path
        )
        XCTAssertFalse(remainingNames.contains { $0.contains(".importing-") })
    }

    private func assertNoImportArtifacts(in applicationSupport: URL) throws {
        let targetDirectory =
            applicationSupport
            .appendingPathComponent("OneBox", isDirectory: true)
            .appendingPathComponent("StockWatch", isDirectory: true)
        let remainingNames = try FileManager.default.contentsOfDirectory(
            atPath: targetDirectory.path
        )
        XCTAssertFalse(remainingNames.contains { $0.contains(".importing-") })
    }

    private func makePreferences() -> StockWatchPreferences {
        let suiteName = "StockWatchBootstrapTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return StockWatchPreferences(defaults: defaults, legacyDefaults: nil)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("StockWatchBootstrapTests.\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }

    private func prepareInvalidRestoreDatabase(atPath path: String) async throws {
        let database = try MarketDatabase.open(atPath: path)
        try await database.replaceWatchlist(with: [Instrument.initialWatchlist[0]])
        try await database.close()
        try SQLiteTestSupport.execute(
            "UPDATE watchlist SET position = 999;",
            atPath: path
        )
    }

    private func waitForStore(in bootstrap: StockWatchBootstrap) async throws -> MonitorStore {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(1))
        while clock.now < deadline {
            if let store = bootstrap.store {
                return store
            }
            await Task.yield()
        }
        throw TestError.storeDidNotStart
    }

    private func waitForFailure(in bootstrap: StockWatchBootstrap) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(1))
        while clock.now < deadline {
            if bootstrap.failure != nil {
                return
            }
            await Task.yield()
        }
        throw TestError.startupDidNotFail
    }
}

private enum TestError: Error {
    case closeDidNotSuspend
    case databaseUnavailable
    case retryOpenDidNotSuspend
    case quoteCacheClearDidNotStart
    case snapshotCopyDidNotComplete
    case storeDidNotStart
    case startupDidNotFail
}

private actor QuoteCacheClearProbe {
    private var started = false
    private(set) var wasCancelled = false

    func clear() async throws {
        started = true
        do {
            try await Task.sleep(for: .seconds(3_600))
        } catch is CancellationError {
            wasCancelled = true
            throw CancellationError()
        }
    }

    func waitUntilStarted() async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(1))
        while !started, clock.now < deadline {
            await Task.yield()
        }
        guard started else { throw TestError.quoteCacheClearDidNotStart }
    }
}

private actor ImportStageGate {
    private var snapshotCopied = false
    private var resumeContinuation: CheckedContinuation<Void, Never>?

    func observe(_ stage: StockWatchStorageImportStage) async {
        switch stage {
        case .snapshotCopied:
            snapshotCopied = true
        }
        await withCheckedContinuation { continuation in
            resumeContinuation = continuation
        }
    }

    func waitUntilSnapshotCopied() async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(1))
        while !snapshotCopied, clock.now < deadline {
            await Task.yield()
        }
        guard snapshotCopied else { throw TestError.snapshotCopyDidNotComplete }
    }

    func resume() {
        resumeContinuation?.resume()
        resumeContinuation = nil
    }
}

private actor RetryingDatabaseFactory {
    private let databasePath: String
    private(set) var attemptCount = 0

    init(databasePath: String) {
        self.databasePath = databasePath
    }

    func open() throws -> MarketDatabase {
        attemptCount += 1
        if attemptCount == 1 {
            throw TestError.databaseUnavailable
        }
        return try MarketDatabase.open(atPath: databasePath)
    }
}

@MainActor
private final class PreferencesFactoryProbe {
    private(set) var creationCount = 0

    func make() -> StockWatchPreferences {
        creationCount += 1
        let suiteName = "PreferencesFactoryProbe.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return StockWatchPreferences(defaults: defaults, legacyDefaults: nil)
    }
}

private actor CountingDatabaseFactory {
    private let databasePath: String
    private(set) var attemptCount = 0

    init(databasePath: String) {
        self.databasePath = databasePath
    }

    func open() throws -> MarketDatabase {
        attemptCount += 1
        return try MarketDatabase.open(atPath: databasePath)
    }
}

private actor SuspendingDatabaseClose {
    private var continuation: CheckedContinuation<Void, Never>?
    private var isCloseSuspended = false
    private var resumeRequested = false

    func close(_ database: MarketDatabase) async throws {
        isCloseSuspended = true
        if !resumeRequested {
            await withCheckedContinuation { continuation in
                self.continuation = continuation
            }
        }
        try await database.close()
    }

    func waitUntilCloseIsSuspended() async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(1))
        while !isCloseSuspended, clock.now < deadline {
            await Task.yield()
        }
        guard isCloseSuspended else { throw TestError.closeDidNotSuspend }
    }

    func resumeClose() {
        resumeRequested = true
        continuation?.resume()
        continuation = nil
    }
}

private actor SuspendingRetryDatabaseFactory {
    private let databasePath: String
    private var attemptCount = 0
    private var suspendedRetry:
        (
            database: MarketDatabase,
            continuation: CheckedContinuation<MarketDatabase, Never>
        )?

    init(databasePath: String) {
        self.databasePath = databasePath
    }

    func open() async throws -> MarketDatabase {
        attemptCount += 1
        guard attemptCount > 1 else {
            throw TestError.databaseUnavailable
        }
        let database = try MarketDatabase.open(atPath: databasePath)
        return await withCheckedContinuation { continuation in
            suspendedRetry = (database, continuation)
        }
    }

    func waitUntilRetryOpenIsSuspended() async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(1))
        while suspendedRetry == nil, clock.now < deadline {
            await Task.yield()
        }
        guard suspendedRetry != nil else { throw TestError.retryOpenDidNotSuspend }
    }

    func resumeRetryOpen() {
        guard let suspendedRetry else { return }
        self.suspendedRetry = nil
        suspendedRetry.continuation.resume(returning: suspendedRetry.database)
    }
}

private actor CountingDatabaseClose {
    private(set) var closeCount = 0

    func close(_ database: MarketDatabase) async throws {
        closeCount += 1
        try await database.close()
    }
}

private actor FailFirstDatabaseClose {
    private var closeCount = 0

    func close(_ database: MarketDatabase) async throws {
        closeCount += 1
        guard closeCount > 1 else { throw TestCloseError.forced }
        try await database.close()
    }
}

private enum TestCloseError: LocalizedError, Sendable {
    case forced

    var errorDescription: String? { "forced database close failure" }
}

private actor CountingMarketDataClient: MarketDataClient {
    private(set) var fetchCount = 0

    func searchInstruments(matching query: String) async throws -> [Instrument] {
        []
    }

    func fetchQuote(for instrument: Instrument) async throws -> QuoteSnapshot {
        fetchCount += 1
        throw URLError(.notConnectedToInternet)
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
