import Combine
import Foundation
import XCTest

@testable import PodPinTool

final class PodPinStoreTests: XCTestCase {
    @MainActor
    func testWarmResumePublishesCacheBeforeRefreshingInTheBackground() async throws {
        let database = try MarketDatabase.inMemory()
        let mediaRoot = temporaryDirectory()
        let defaultsName = "PodPinStoreTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsName))
        defer {
            defaults.removePersistentDomain(forName: defaultsName)
            try? FileManager.default.removeItem(at: mediaRoot)
        }

        let item = try await database.insertItem(makeOnlineItem(contentID: "warm-resume"))
        let store = PodPinStore(
            preferences: AppPreferences(defaults: defaults),
            databaseFactory: { database },
            mediaStoreFactory: { try PodPinMediaStore(rootURL: mediaRoot) }
        )
        await store.start()
        XCTAssertEqual(store.items.map(\.id), [item.id])

        var refreshCount = 0
        let refreshFinished = expectation(description: "Background refresh finished")
        store.itemRefreshTestHook = { _ in refreshCount += 1 }
        store.itemRefreshCompletionTestHook = { _ in refreshFinished.fulfill() }
        store.suspendUI()
        await store.resumeUI()

        XCTAssertEqual(refreshCount, 0)
        XCTAssertEqual(store.items.map(\.id), [item.id])
        XCTAssertEqual(store.itemsPhase, .loaded(.recentlyImported))

        await fulfillment(of: [refreshFinished], timeout: 1)
        XCTAssertEqual(refreshCount, 1)
        XCTAssertEqual(store.items.map(\.id), [item.id])
    }

    @MainActor
    func testWarmRefreshFailureKeepsCachedContentAndReportsInlineError() async throws {
        let database = try MarketDatabase.inMemory()
        let mediaRoot = temporaryDirectory()
        let defaultsName = "PodPinStoreWarmRefreshFailureTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsName))
        defer {
            defaults.removePersistentDomain(forName: defaultsName)
            try? FileManager.default.removeItem(at: mediaRoot)
        }
        let item = try await database.insertItem(makeOnlineItem(contentID: "cached"))
        let store = PodPinStore(
            preferences: AppPreferences(defaults: defaults),
            databaseFactory: { database },
            mediaStoreFactory: { try PodPinMediaStore(rootURL: mediaRoot) }
        )
        await store.start()
        try await database.close()
        let refreshFinished = expectation(description: "Failed refresh finished")
        store.itemRefreshCompletionTestHook = { _ in refreshFinished.fulfill() }

        store.suspendUI()
        await store.resumeUI()
        await fulfillment(of: [refreshFinished], timeout: 1)

        XCTAssertEqual(store.items.map(\.id), [item.id])
        XCTAssertEqual(store.itemsPhase, .loaded(.recentlyImported))
        XCTAssertNotNil(store.userFacingError)
    }

    @MainActor
    func testSettingPlaybackRateUpdatesTheActiveControllerImmediately() throws {
        let defaultsName = "PodPinStoreTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsName))
        defer { defaults.removePersistentDomain(forName: defaultsName) }

        let playbackController = AudioPlaybackController()
        let store = PodPinStore(
            preferences: AppPreferences(defaults: defaults),
            playbackController: playbackController
        )

        store.setPlaybackRate(1.5)

        XCTAssertEqual(store.preferences.playbackRate, 1.5)
        XCTAssertEqual(playbackController.rate, 1.5)
    }

    @MainActor
    func testStartRestoresPersistedPlaybackVolumeToTheController() async throws {
        let defaultsName = "PodPinStoreVolumeTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsName))
        let mediaRoot = temporaryDirectory()
        defer {
            defaults.removePersistentDomain(forName: defaultsName)
            try? FileManager.default.removeItem(at: mediaRoot)
        }
        let preferences = AppPreferences(defaults: defaults)
        preferences.playbackVolume = 0.36
        let controller = AudioPlaybackController()
        let store = PodPinStore(
            preferences: preferences,
            databaseFactory: { try MarketDatabase.inMemory() },
            mediaStoreFactory: { try PodPinMediaStore(rootURL: mediaRoot) },
            playbackController: controller
        )

        await store.start()

        XCTAssertEqual(controller.volume, 0.36)
    }

    @MainActor
    func testStartOpensPersistenceOffTheMainThread() async throws {
        let defaultsName = "PodPinStoreStartupThreadTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsName))
        let mediaRoot = temporaryDirectory()
        let recorder = ThreadRecorder()
        defer {
            defaults.removePersistentDomain(forName: defaultsName)
            try? FileManager.default.removeItem(at: mediaRoot)
        }
        let store = PodPinStore(
            preferences: AppPreferences(defaults: defaults),
            databaseFactory: {
                recorder.recordCurrentThread()
                return try MarketDatabase.inMemory()
            },
            mediaStoreFactory: {
                recorder.recordCurrentThread()
                return try PodPinMediaStore(rootURL: mediaRoot)
            }
        )

        await store.start()

        XCTAssertEqual(recorder.mainThreadValues(), [false, false])
    }

    @MainActor
    func testReturningSurfaceRemainsVisibleWhenInitialSurfaceStartupTaskIsCancelled() async throws {
        let database = try MarketDatabase.inMemory()
        let mediaRoot = temporaryDirectory()
        let defaultsName = "PodPinStoreStartupOwnershipTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsName))
        let factoryGate = SynchronousFactoryGate()
        defer {
            factoryGate.release()
            defaults.removePersistentDomain(forName: defaultsName)
            try? FileManager.default.removeItem(at: mediaRoot)
        }
        let store = PodPinStore(
            preferences: AppPreferences(defaults: defaults),
            databaseFactory: {
                factoryGate.block()
                return database
            },
            mediaStoreFactory: { try PodPinMediaStore(rootURL: mediaRoot) }
        )

        let initialSurface = Task { @MainActor in
            await store.resumeUI()
        }
        await factoryGate.waitUntilBlocked()
        store.suspendUI()
        let returningSurface = Task { @MainActor in
            await store.resumeUI()
        }
        try await Task.sleep(for: .milliseconds(10))

        initialSurface.cancel()
        factoryGate.release()
        await returningSurface.value

        XCTAssertEqual(store.startupPhase, .ready)
        XCTAssertTrue(store.isUISurfaceVisibleForTesting)
        await store.shutdown()
    }

    @MainActor
    func testPlaybackPersistenceUpdatesVisibleItemWithoutChangingCollection() async throws {
        let database = try MarketDatabase.inMemory()
        let mediaRoot = temporaryDirectory()
        let defaultsName = "PodPinStorePlaybackRefreshTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsName))
        defer {
            defaults.removePersistentDomain(forName: defaultsName)
            try? FileManager.default.removeItem(at: mediaRoot)
        }
        let controller = AudioPlaybackController()
        let item = try await database.insertItem(
            makeOnlineItem(contentID: "live-playback-refresh", duration: 120)
        )
        let store = PodPinStore(
            preferences: AppPreferences(defaults: defaults),
            databaseFactory: { database },
            mediaStoreFactory: { try PodPinMediaStore(rootURL: mediaRoot) },
            playbackController: controller
        )
        await store.start()
        XCTAssertEqual(store.items.first(where: { $0.id == item.id })?.playbackPosition, 0)

        var listeningHistory = ListeningHistory()
        listeningHistory.record(from: 0, to: 12, duration: 120)
        controller.onPlaybackPositionChanged?(item.id, 12, listeningHistory, false)
        for _ in 0..<100 {
            if try await database.item(id: item.id)?.playbackPosition == 12 { break }
            try await Task.sleep(for: .milliseconds(10))
        }

        let persistedItem = try await database.item(id: item.id)
        XCTAssertEqual(persistedItem?.playbackPosition, 12)
        XCTAssertEqual(persistedItem?.listeningHistory, listeningHistory)
        XCTAssertEqual(store.items.first(where: { $0.id == item.id })?.playbackPosition, 12)
        XCTAssertEqual(
            store.items.first(where: { $0.id == item.id })?.listeningHistory, listeningHistory)
    }

    @MainActor
    func testStaleFolderRefreshCannotReplaceNewerSelection() async throws {
        let database = try MarketDatabase.inMemory()
        let mediaRoot = temporaryDirectory()
        let defaultsName = "PodPinStoreTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsName))
        defer {
            defaults.removePersistentDomain(forName: defaultsName)
            try? FileManager.default.removeItem(at: mediaRoot)
        }

        let firstFolder = try await database.createFolder(named: "A")
        let secondFolder = try await database.createFolder(named: "B")
        let firstItem = try await database.insertItem(
            makeOnlineItem(contentID: "folder-a", folderID: firstFolder.id)
        )
        let secondItem = try await database.insertItem(
            makeOnlineItem(contentID: "folder-b", folderID: secondFolder.id)
        )
        let gate = ItemRefreshGate(blockedFolderID: firstFolder.id)
        let store = PodPinStore(
            preferences: AppPreferences(defaults: defaults),
            databaseFactory: { database },
            mediaStoreFactory: { try PodPinMediaStore(rootURL: mediaRoot) }
        )
        await store.start()
        XCTAssertNil(store.startupError)
        store.itemRefreshTestHook = { collection in
            await gate.blockIfNeeded(collection.defaultImportFolderID)
        }
        store.itemRefreshCompletionTestHook = { collection in
            Task { await gate.recordCompletion(for: collection.defaultImportFolderID) }
        }

        store.selectedFolderID = firstFolder.id
        await gate.waitUntilBlocked()

        store.selectedFolderID = secondFolder.id
        try await waitUntil { store.items.map(\.id) == [secondItem.id] }
        await gate.waitUntilCompleted(for: secondFolder.id)

        await gate.releaseBlockedRefresh()
        await gate.waitUntilCompleted(for: firstFolder.id)

        XCTAssertEqual(store.selectedFolderID, secondFolder.id)
        XCTAssertEqual(store.items.map(\.id), [secondItem.id])
        XCTAssertNotEqual(store.items.map(\.id), [firstItem.id])
    }

    @MainActor
    func testLaterOnlineResolutionRemainsTheCurrentPlaybackItem() async throws {
        let database = try MarketDatabase.inMemory()
        let mediaRoot = temporaryDirectory()
        let defaultsName = "PodPinStoreTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsName))
        defer {
            defaults.removePersistentDomain(forName: defaultsName)
            try? FileManager.default.removeItem(at: mediaRoot)
        }

        let importer = DelayedFirstStreamImporter()
        let store = PodPinStore(
            preferences: AppPreferences(defaults: defaults),
            databaseFactory: { database },
            mediaStoreFactory: { try PodPinMediaStore(rootURL: mediaRoot) },
            importer: importer
        )
        let first = try await database.insertItem(makeOnlineItem(contentID: "video-a"))
        let second = try await database.insertItem(makeOnlineItem(contentID: "video-b"))
        await store.start()
        XCTAssertNil(store.startupError)

        let firstPlay = Task { @MainActor in
            await store.play(first)
        }
        await importer.waitUntilFirstResolutionStarts()

        await store.play(second)
        XCTAssertEqual(store.currentItem?.id, second.id)
        let currentAfterSecondResolution = try await database.currentPlaybackItem()
        XCTAssertEqual(currentAfterSecondResolution?.id, second.id)

        await importer.releaseFirstResolution()
        await firstPlay.value

        XCTAssertEqual(store.currentItem?.id, second.id)
        let currentAfterFirstResolutionCompletes = try await database.currentPlaybackItem()
        XCTAssertEqual(currentAfterFirstResolutionCompletes?.id, second.id)
    }

    @MainActor
    func testShutdownWaitsForOwnedPlaybackResolutionTask() async throws {
        let database = try MarketDatabase.inMemory()
        let mediaRoot = temporaryDirectory()
        let defaultsName = "PodPinStoreTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsName))
        defer {
            defaults.removePersistentDomain(forName: defaultsName)
            try? FileManager.default.removeItem(at: mediaRoot)
        }

        let importer = DelayedFirstStreamImporter()
        let store = PodPinStore(
            preferences: AppPreferences(defaults: defaults),
            databaseFactory: { database },
            mediaStoreFactory: { try PodPinMediaStore(rootURL: mediaRoot) },
            importer: importer
        )
        let item = try await database.insertItem(makeOnlineItem(contentID: "video-a"))
        await store.start()
        store.playNow(item)
        await importer.waitUntilFirstResolutionStarts()

        let completion = CompletionProbe()
        let shutdownTask = Task { @MainActor in
            await store.shutdown()
            await completion.markCompleted()
        }
        try await Task.sleep(for: .milliseconds(20))
        let completedBeforeRelease = await completion.isCompleted()
        XCTAssertFalse(completedBeforeRelease)

        await importer.releaseFirstResolution()
        await shutdownTask.value
        let completedAfterRelease = await completion.isCompleted()
        XCTAssertTrue(completedAfterRelease)
    }

    @MainActor
    func testShutdownWaitsForStoreOwnedImport() async throws {
        let database = try MarketDatabase.inMemory()
        let mediaRoot = temporaryDirectory()
        let defaultsName = "PodPinStoreImportShutdownTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsName))
        defer {
            defaults.removePersistentDomain(forName: defaultsName)
            try? FileManager.default.removeItem(at: mediaRoot)
        }
        let importer = DelayedFirstStreamImporter()
        let store = PodPinStore(
            preferences: AppPreferences(defaults: defaults),
            databaseFactory: { database },
            mediaStoreFactory: { try PodPinMediaStore(rootURL: mediaRoot) },
            importer: importer
        )
        await store.start()
        let metadata = ImportedAudioMetadata(
            platform: .fixture,
            contentID: "video-a",
            sourceURL: URL(string: "https://fixture.podpin.local/video-a")!,
            title: "Video A",
            author: "PodPin",
            artworkURL: nil,
            duration: 60
        )
        let discovery = ImportDiscovery(
            sourceURL: metadata.sourceURL,
            primaryItem: metadata
        )
        store.startImportDiscovery(
            discovery,
            selectedContentIDs: [metadata.contentID],
            into: LibraryFolder.inboxID,
            choice: .stream
        ) { _ in }
        await importer.waitUntilFirstResolutionStarts()

        let completion = CompletionProbe()
        let shutdownTask = Task { @MainActor in
            await store.shutdown()
            await completion.markCompleted()
        }
        try await Task.sleep(for: .milliseconds(20))
        let completedBeforeRelease = await completion.isCompleted()
        XCTAssertFalse(completedBeforeRelease)

        await importer.releaseFirstResolution()
        await shutdownTask.value
        let completedAfterRelease = await completion.isCompleted()
        XCTAssertTrue(completedAfterRelease)
    }

    @MainActor
    func testMissingDownloadedFileBecomesRetryableFailure() async throws {
        let database = try MarketDatabase.inMemory()
        let mediaRoot = temporaryDirectory()
        let defaultsName = "PodPinStoreMissingDownloadTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsName))
        defer {
            defaults.removePersistentDomain(forName: defaultsName)
            try? FileManager.default.removeItem(at: mediaRoot)
        }
        let inserted = try await database.insertItem(
            makeOnlineItem(contentID: "missing-download")
        )
        let missing = try await database.updateDownloadState(
            for: inserted.id,
            state: .available,
            localMediaRelativePath: "\(inserted.id.uuidString)/audio.m4a",
            duration: 60
        )
        let importer = CountingStreamImporter()
        let store = PodPinStore(
            preferences: AppPreferences(defaults: defaults),
            databaseFactory: { database },
            mediaStoreFactory: { try PodPinMediaStore(rootURL: mediaRoot) },
            importer: importer
        )
        await store.start()

        await store.play(missing)

        let persisted = try await database.item(id: inserted.id)
        XCTAssertEqual(persisted?.downloadState, .failed)
        XCTAssertNil(persisted?.localMediaRelativePath)
        XCTAssertEqual(
            store.items.first(where: { $0.id == inserted.id })?.downloadState,
            .failed
        )
        let resolutionCount = await importer.resolutionCount()
        XCTAssertEqual(resolutionCount, 1)
        XCTAssertEqual(store.playbackPresentation.snapshot.item?.id, inserted.id)
    }

    @MainActor
    func testExpiredOnlinePlaybackRefreshesTheStreamOnlyOnce() async throws {
        let database = try MarketDatabase.inMemory()
        let mediaRoot = temporaryDirectory()
        let defaultsName = "PodPinStoreTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsName))
        defer {
            defaults.removePersistentDomain(forName: defaultsName)
            try? FileManager.default.removeItem(at: mediaRoot)
        }

        let importer = CountingStreamImporter()
        let playbackController = AudioPlaybackController()
        let store = PodPinStore(
            preferences: AppPreferences(defaults: defaults),
            databaseFactory: { database },
            mediaStoreFactory: { try PodPinMediaStore(rootURL: mediaRoot) },
            importer: importer,
            playbackController: playbackController
        )
        let item = try await database.insertItem(makeOnlineItem(contentID: "expiring-stream"))
        await store.start()

        await store.play(item)
        await importer.waitUntilResolutionCount(1)
        playbackController.onPlaybackFailed?(item.id, "expired", 403)
        await importer.waitUntilResolutionCount(2)

        playbackController.onPlaybackFailed?(item.id, "expired again", 403)
        try await Task.sleep(for: .milliseconds(100))
        let resolutionCount = await importer.resolutionCount()
        XCTAssertEqual(resolutionCount, 2)
    }

    @MainActor
    func testOnlinePlaybackReusesTheShortLivedResolvedStreamCache() async throws {
        let database = try MarketDatabase.inMemory()
        let mediaRoot = temporaryDirectory()
        let defaultsName = "PodPinStoreStreamCacheTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsName))
        defer {
            defaults.removePersistentDomain(forName: defaultsName)
            try? FileManager.default.removeItem(at: mediaRoot)
        }

        let importer = CountingStreamImporter()
        let store = PodPinStore(
            preferences: AppPreferences(defaults: defaults),
            databaseFactory: { database },
            mediaStoreFactory: { try PodPinMediaStore(rootURL: mediaRoot) },
            importer: importer
        )
        let item = try await database.insertItem(makeOnlineItem(contentID: "cache-reuse"))
        await store.start()

        await store.play(item)
        await store.play(item)

        let resolutionCount = await importer.resolutionCount()
        XCTAssertEqual(resolutionCount, 1)
    }

    @MainActor
    func testDownloadReservationRejectsASecondTaskAndAllowsRetryAfterFailure() async throws {
        let database = try MarketDatabase.inMemory()
        let mediaRoot = temporaryDirectory()
        let defaultsName = "PodPinStoreTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsName))
        defer {
            defaults.removePersistentDomain(forName: defaultsName)
            try? FileManager.default.removeItem(at: mediaRoot)
        }

        let importer = GatedDownloadImporter()
        let store = PodPinStore(
            preferences: AppPreferences(defaults: defaults),
            databaseFactory: { database },
            mediaStoreFactory: { try PodPinMediaStore(rootURL: mediaRoot) },
            importer: importer
        )
        let first = try await database.insertItem(makeOnlineItem(contentID: "download-a"))
        let second = try await database.insertItem(makeOnlineItem(contentID: "download-b"))
        try await database.setCurrentPlaybackItem(first.id)
        await store.start()

        store.startDownload(first)
        await importer.waitUntilDownloadStarts(contentID: first.contentID, attempt: 1)
        XCTAssertEqual(
            store.playbackPresentation.identity.snapshot.item?.downloadState, .downloading)
        store.startDownload(second)

        XCTAssertEqual(store.activeDownloadItemID, first.id)
        let secondAttemptsWhileFirstIsReserved = await importer.downloadAttempts(
            for: second.contentID)
        XCTAssertEqual(secondAttemptsWhileFirstIsReserved, 0)

        await importer.failDownload(contentID: first.contentID, attempt: 1)
        try await waitUntil { store.activeDownloadItemID == nil }
        let failed = try await database.item(id: first.id)
        XCTAssertEqual(failed?.downloadState, .failed)
        XCTAssertEqual(store.playbackPresentation.identity.snapshot.item?.downloadState, .failed)

        store.dismissError()
        store.startDownload(first)
        await importer.waitUntilDownloadStarts(contentID: first.contentID, attempt: 2)
        await importer.succeedDownload(contentID: first.contentID, attempt: 2)
        try await waitUntil { store.activeDownloadItemID == nil }

        let downloaded = try await database.item(id: first.id)
        XCTAssertEqual(downloaded?.downloadState, .available)
        XCTAssertEqual(downloaded?.storageKind, .offline)
        XCTAssertEqual(store.playbackPresentation.identity.snapshot.item?.downloadState, .available)
        let secondAttemptsAfterFirstRetries = await importer.downloadAttempts(for: second.contentID)
        XCTAssertEqual(secondAttemptsAfterFirstRetries, 0)
    }

    @MainActor
    func testDownloadProgressPublishesThroughDedicatedSession() async throws {
        let database = try MarketDatabase.inMemory()
        let mediaRoot = temporaryDirectory()
        let defaultsName = "PodPinStoreTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsName))
        defer {
            defaults.removePersistentDomain(forName: defaultsName)
            try? FileManager.default.removeItem(at: mediaRoot)
        }

        let importer = GatedDownloadImporter()
        let store = PodPinStore(
            preferences: AppPreferences(defaults: defaults),
            databaseFactory: { database },
            mediaStoreFactory: { try PodPinMediaStore(rootURL: mediaRoot) },
            importer: importer
        )
        let item = try await database.insertItem(makeOnlineItem(contentID: "download-progress"))
        await store.start()
        store.startDownload(item)
        await importer.waitUntilDownloadStarts(contentID: item.contentID, attempt: 1)

        let publication = expectation(description: "Download progress publishes")
        let cancellable = store.downloadSession.objectWillChange.sink {
            publication.fulfill()
        }
        await importer.reportProgress(
            DownloadProgressSnapshot(fraction: 0.42, bytesPerSecond: 1_500_000),
            contentID: item.contentID,
            attempt: 1
        )

        await fulfillment(of: [publication], timeout: 1)
        XCTAssertEqual(store.downloadSession.progress, 0.42)
        XCTAssertEqual(store.downloadSession.bytesPerSecond, 1_500_000)
        _ = cancellable
        await importer.succeedDownload(contentID: item.contentID, attempt: 1)
    }

    @MainActor
    func testDownloadProgressCoalescesBurstUpdates() async throws {
        let database = try MarketDatabase.inMemory()
        let mediaRoot = temporaryDirectory()
        let defaultsName = "PodPinStoreTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsName))
        defer {
            defaults.removePersistentDomain(forName: defaultsName)
            try? FileManager.default.removeItem(at: mediaRoot)
        }

        let importer = GatedDownloadImporter()
        let store = PodPinStore(
            preferences: AppPreferences(defaults: defaults),
            databaseFactory: { database },
            mediaStoreFactory: { try PodPinMediaStore(rootURL: mediaRoot) },
            importer: importer
        )
        let item = try await database.insertItem(makeOnlineItem(contentID: "progress-burst"))
        await store.start()
        store.startDownload(item)
        await importer.waitUntilDownloadStarts(contentID: item.contentID, attempt: 1)

        var publicationCount = 0
        let completionPublication = expectation(description: "Completion publishes 100 percent")
        let cancellable = store.downloadSession.$snapshot.dropFirst().sink { snapshot in
            publicationCount += 1
            if snapshot.fraction == 1 {
                completionPublication.fulfill()
            }
        }
        for index in 1...87 {
            await importer.reportProgress(
                DownloadProgressSnapshot(
                    fraction: Double(index) / 100,
                    bytesPerSecond: Double(index)
                ),
                contentID: item.contentID,
                attempt: 1
            )
        }

        try await Task.sleep(for: .milliseconds(250))
        XCTAssertLessThanOrEqual(publicationCount, 4)
        XCTAssertEqual(store.downloadSession.progress, 0.87)

        await importer.succeedDownload(contentID: item.contentID, attempt: 1)
        await fulfillment(of: [completionPublication], timeout: 1)
        XCTAssertLessThanOrEqual(publicationCount, 5)
        _ = cancellable
    }

    @MainActor
    func testCollectionDownloadUpsertsAtomicallyAndContinuesAfterItemFailure() async throws {
        let database = try MarketDatabase.inMemory()
        let mediaRoot = temporaryDirectory()
        let defaultsName = "PodPinStoreTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsName))
        defer {
            defaults.removePersistentDomain(forName: defaultsName)
            try? FileManager.default.removeItem(at: mediaRoot)
        }

        let importer = GatedDownloadImporter()
        let store = PodPinStore(
            preferences: AppPreferences(defaults: defaults),
            databaseFactory: { database },
            mediaStoreFactory: { try PodPinMediaStore(rootURL: mediaRoot) },
            importer: importer
        )
        await store.start()
        let sourceURL = URL(string: "https://fixture.podpin.local/collection")!
        let metadata = (1...3).map { index in
            ImportedAudioMetadata(
                platform: .fixture,
                contentID: "part-\(index)",
                sourceURL: sourceURL.appending(path: "part-\(index)"),
                title: "Part \(index)",
                author: "PodPin",
                artworkURL: nil,
                duration: 1
            )
        }
        let discovery = ImportDiscovery(
            sourceURL: sourceURL,
            groupTitle: "Three parts",
            primaryItem: metadata[0],
            remainingItems: Array(metadata.dropFirst())
        )

        let imported = await store.importDiscovery(
            discovery,
            selectedContentIDs: Set(metadata.map(\.contentID)),
            into: LibraryFolder.inboxID,
            choice: .download
        )

        XCTAssertEqual(imported?.map(\.contentID), ["part-1", "part-2", "part-3"])
        let initiallySaved = try await database.listAllItems()
        XCTAssertEqual(initiallySaved.count, 3)
        await importer.waitUntilDownloadStarts(contentID: "part-1", attempt: 1)
        await importer.failDownload(contentID: "part-1", attempt: 1)
        await importer.waitUntilDownloadStarts(contentID: "part-2", attempt: 1)
        await importer.succeedDownload(contentID: "part-2", attempt: 1)
        await importer.waitUntilDownloadStarts(contentID: "part-3", attempt: 1)
        await importer.succeedDownload(contentID: "part-3", attempt: 1)
        try await waitUntil { store.activeDownloadItemID == nil }

        let saved = try await database.listAllItems()
        XCTAssertEqual(saved.first(where: { $0.contentID == "part-1" })?.downloadState, .failed)
        XCTAssertEqual(saved.first(where: { $0.contentID == "part-2" })?.downloadState, .available)
        XCTAssertEqual(saved.first(where: { $0.contentID == "part-3" })?.downloadState, .available)
    }

    @MainActor
    func testCancellingCollectionDownloadLeavesCurrentAndRemainingItemsOnline() async throws {
        let database = try MarketDatabase.inMemory()
        let mediaRoot = temporaryDirectory()
        let defaultsName = "PodPinStoreTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsName))
        defer {
            defaults.removePersistentDomain(forName: defaultsName)
            try? FileManager.default.removeItem(at: mediaRoot)
        }

        let importer = CancellableDownloadImporter()
        let store = PodPinStore(
            preferences: AppPreferences(defaults: defaults),
            databaseFactory: { database },
            mediaStoreFactory: { try PodPinMediaStore(rootURL: mediaRoot) },
            importer: importer
        )
        await store.start()
        let sourceURL = URL(string: "https://fixture.podpin.local/cancellable")!
        let metadata = (1...2).map { index in
            ImportedAudioMetadata(
                platform: .fixture,
                contentID: "cancel-part-\(index)",
                sourceURL: sourceURL.appending(path: "part-\(index)"),
                title: "Part \(index)",
                author: "PodPin",
                artworkURL: nil,
                duration: 1
            )
        }
        let discovery = ImportDiscovery(
            sourceURL: sourceURL,
            groupTitle: "Cancellable parts",
            primaryItem: metadata[0],
            remainingItems: [metadata[1]]
        )

        _ = await store.importDiscovery(
            discovery,
            selectedContentIDs: Set(metadata.map(\.contentID)),
            into: LibraryFolder.inboxID,
            choice: .download
        )
        await importer.waitUntilFirstDownloadStarts()

        store.cancelDownload()
        try await waitUntil { store.activeDownloadItemID == nil }

        let saved = try await database.listAllItems()
        XCTAssertEqual(saved.count, 2)
        XCTAssertTrue(saved.allSatisfy { $0.storageKind == .online })
        XCTAssertTrue(saved.allSatisfy { $0.downloadState == .notRequested })
        let secondAttempts = await importer.downloadAttempts(for: "cancel-part-2")
        XCTAssertEqual(secondAttempts, 0)
    }

    @MainActor
    func testProbeExtractsThePublicLinkFromADouyinSharePhrase() async throws {
        let defaultsName = "PodPinStoreTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsName))
        defer { defaults.removePersistentDomain(forName: defaultsName) }

        let importer = CapturingProbeImporter()
        let store = PodPinStore(
            preferences: AppPreferences(defaults: defaults),
            importer: importer
        )
        let sharePhrase =
            "2.58 复制打开抖音，看看【趋势天哥的作品】韩国指数暴跌探底回升，全球科技企稳了吗？ # A股... https://v.douyin.com/Ne1f5EXZW4Q/ :8pm B@G.IV Wmd:/ 10/20"

        let metadata = await store.probe(urlText: sharePhrase)

        XCTAssertEqual(metadata?.sourceURL.absoluteString, "https://v.douyin.com/Ne1f5EXZW4Q/")
        let probedURLs = await importer.allProbedURLs()
        XCTAssertEqual(probedURLs, [URL(string: "https://v.douyin.com/Ne1f5EXZW4Q/")!])
    }

    @MainActor
    func testVerificationRequestRetriesTheOriginalProbe() async throws {
        let defaultsName = "PodPinStoreTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsName))
        defer { defaults.removePersistentDomain(forName: defaultsName) }

        let importer = VerificationThenSuccessImporter()
        let store = PodPinStore(
            preferences: AppPreferences(defaults: defaults),
            importer: importer
        )
        let sourceURL = "https://v.douyin.com/Ne1f5EXZW4Q/"

        let firstAttempt = await store.probe(urlText: sourceURL)
        XCTAssertNil(firstAttempt)
        XCTAssertEqual(store.verificationRequest?.url.absoluteString, sourceURL)

        let metadata = await store.retryVerification()

        XCTAssertEqual(metadata?.sourceURL.absoluteString, sourceURL)
        XCTAssertNil(store.verificationRequest)
        let probeCount = await importer.probeCount()
        XCTAssertEqual(probeCount, 2)
    }

    @MainActor
    func testShutdownWaitsForActiveDownloadCancellationAndPersistsItsState() async throws {
        let database = try MarketDatabase.inMemory()
        let mediaRoot = temporaryDirectory()
        let defaultsName = "PodPinStoreTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsName))
        defer {
            defaults.removePersistentDomain(forName: defaultsName)
            try? FileManager.default.removeItem(at: mediaRoot)
        }

        let importer = CancellableDownloadImporter()
        let store = PodPinStore(
            preferences: AppPreferences(defaults: defaults),
            databaseFactory: { database },
            mediaStoreFactory: { try PodPinMediaStore(rootURL: mediaRoot) },
            importer: importer
        )
        let item = try await database.insertItem(makeOnlineItem(contentID: "shutdown-download"))
        await store.start()
        store.startDownload(item)
        await importer.waitUntilFirstDownloadStarts()

        await store.shutdown()

        XCTAssertNil(store.activeDownloadItemID)
        let persistedItem = try await database.item(id: item.id)
        XCTAssertEqual(persistedItem?.downloadState, .notRequested)
        let downloadAttempts = await importer.downloadAttempts(for: item.contentID)
        XCTAssertEqual(downloadAttempts, 1)
    }

    @MainActor
    func testShutdownCancelsAndWaitsForInFlightLibraryOperation() async throws {
        let database = try MarketDatabase.inMemory()
        let mediaRoot = temporaryDirectory()
        let defaultsName = "PodPinStoreLibraryShutdownTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsName))
        defer {
            defaults.removePersistentDomain(forName: defaultsName)
            try? FileManager.default.removeItem(at: mediaRoot)
        }
        let store = PodPinStore(
            preferences: AppPreferences(defaults: defaults),
            databaseFactory: { database },
            mediaStoreFactory: { try PodPinMediaStore(rootURL: mediaRoot) }
        )
        await store.start()
        let gate = LibraryOperationGate()
        store.performLibraryOperation(timeout: .seconds(30)) {
            await gate.block()
            guard !Task.isCancelled else { return }
            _ = try? await database.createFolder(named: "Late mutation")
        }
        await gate.waitUntilBlocked()

        let completion = CompletionProbe()
        let shutdownTask = Task { @MainActor in
            await store.shutdown()
            await completion.markCompleted()
        }
        try await Task.sleep(for: .milliseconds(20))
        let completedWhileOperationWasBlocked = await completion.isCompleted()
        XCTAssertFalse(completedWhileOperationWasBlocked)

        await gate.release()
        await shutdownTask.value

        let folders = try await database.allFolders()
        XCTAssertFalse(folders.contains(where: { $0.name == "Late mutation" }))
        let completedAfterOperationExited = await completion.isCompleted()
        XCTAssertTrue(completedAfterOperationExited)
    }

    @MainActor
    func testBrowserAccessRequiresExplicitProfileAndRetriesOnlyOnce() async throws {
        let defaultsName = "PodPinStoreTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsName))
        defer { defaults.removePersistentDomain(forName: defaultsName) }
        let root = URL(fileURLWithPath: "/tmp/test-browser", isDirectory: true)
        let profile = BrowserProfile(
            browser: .chrome,
            directoryName: "Default",
            displayName: "Default",
            userDataURL: root
        )
        let importer = ExplicitBrowserRetryImporter()
        let authorizer = StubBrowserAccessAuthorizer(profile: profile)
        let store = PodPinStore(
            preferences: AppPreferences(defaults: defaults),
            importer: importer,
            browserAccessAuthorizer: authorizer
        )
        let sourceURL = "https://v.douyin.com/Ne1f5EXZW4Q/"

        let firstResult = await store.probe(urlText: sourceURL)
        XCTAssertNil(firstResult)
        XCTAssertFalse(store.hasRequestedBrowserProfiles)
        XCTAssertTrue(store.browserProfiles.isEmpty)

        store.discoverBrowserProfiles()
        try await waitUntil { store.browserProfiles == [profile] }
        let retriesBeforeSelection = await importer.browserRetryCount()
        XCTAssertEqual(retriesBeforeSelection, 0)

        let discovery = await store.retryBrowserAccess(using: profile)

        XCTAssertEqual(discovery?.primaryItem.contentID, "7667887133545205043")
        let retriesAfterSelection = await importer.browserRetryCount()
        XCTAssertEqual(retriesAfterSelection, 1)
        XCTAssertNil(store.verificationRequest)
        store.discardPendingBrowserAccess()
    }

    @MainActor
    func testProbingANewLinkRevokesPendingBrowserAccess() async throws {
        let defaultsName = "PodPinStoreBrowserScopeTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsName))
        defer { defaults.removePersistentDomain(forName: defaultsName) }
        let root = URL(fileURLWithPath: "/tmp/test-browser", isDirectory: true)
        let profile = BrowserProfile(
            browser: .chrome,
            directoryName: "Default",
            displayName: "Default",
            userDataURL: root
        )
        let importer = ExplicitBrowserRetryImporter()
        let store = PodPinStore(
            preferences: AppPreferences(defaults: defaults),
            importer: importer,
            browserAccessAuthorizer: StubBrowserAccessAuthorizer(profile: profile)
        )
        let firstURL = "https://v.douyin.com/Ne1f5EXZW4Q/"
        _ = await store.probe(urlText: firstURL)
        _ = await store.retryBrowserAccess(using: profile)
        XCTAssertTrue(store.hasPendingBrowserAccess)

        _ = await store.probe(urlText: "https://v.douyin.com/another-public-item/")

        XCTAssertFalse(store.hasPendingBrowserAccess)
    }

    @MainActor
    func testCancellingBrowserAuthorizationDoesNotDispatchRetry() async throws {
        let defaultsName = "PodPinStoreBrowserCancellationTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsName))
        defer { defaults.removePersistentDomain(forName: defaultsName) }
        let root = URL(fileURLWithPath: "/tmp/test-browser", isDirectory: true)
        let profile = BrowserProfile(
            browser: .chrome,
            directoryName: "Default",
            displayName: "Default",
            userDataURL: root
        )
        let sourceURL = URL(string: "https://v.douyin.com/Ne1f5EXZW4Q/")!
        let importer = ExplicitBrowserRetryImporter()
        let authorizer = DelayedBrowserAccessAuthorizer(
            profile: profile,
            sourceURL: sourceURL
        )
        let store = PodPinStore(
            preferences: AppPreferences(defaults: defaults),
            importer: importer,
            browserAccessAuthorizer: authorizer
        )
        _ = await store.probe(urlText: sourceURL.absoluteString)

        let retryTask = Task { @MainActor in
            await store.retryBrowserAccess(using: profile)
        }
        await authorizer.waitUntilAuthorizationStarts()
        retryTask.cancel()
        await authorizer.releaseAuthorization()
        let discovery = await retryTask.value

        XCTAssertNil(discovery)
        let retryCount = await importer.browserRetryCount()
        XCTAssertEqual(retryCount, 0)
        let leaseWasRevoked = await authorizer.leaseWasRevoked()
        XCTAssertTrue(leaseWasRevoked)
    }

    @MainActor
    func testVerificationRequestRetriesTheOriginalStreamResolution() async throws {
        let database = try MarketDatabase.inMemory()
        let mediaRoot = temporaryDirectory()
        let defaultsName = "PodPinStoreTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsName))
        defer {
            defaults.removePersistentDomain(forName: defaultsName)
            try? FileManager.default.removeItem(at: mediaRoot)
        }

        let importer = VerificationThenStreamImporter()
        let store = PodPinStore(
            preferences: AppPreferences(defaults: defaults),
            databaseFactory: { database },
            mediaStoreFactory: { try PodPinMediaStore(rootURL: mediaRoot) },
            importer: importer
        )
        let item = try await database.insertItem(makeOnlineItem(contentID: "verify-stream"))
        await store.start()

        await store.play(item)
        XCTAssertEqual(store.verificationRequest?.url, item.sourceURL)

        _ = await store.retryVerification()

        XCTAssertNil(store.verificationRequest)
        let resolutionCount = await importer.resolutionCount()
        XCTAssertEqual(resolutionCount, 2)
    }

    @MainActor
    private func temporaryDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PodPinStoreTests-\(UUID().uuidString)", isDirectory: true)
        return directory
    }

    private func makeOnlineItem(
        contentID: String,
        folderID: UUID = LibraryFolder.inboxID,
        duration: TimeInterval = 1
    ) -> AudioItem {
        AudioItem(
            platform: .fixture,
            contentID: contentID,
            sourceURL: URL(string: "https://fixture.podpin.local/\(contentID)")!,
            title: contentID,
            author: "PodPin",
            duration: duration,
            folderID: folderID
        )
    }

    @MainActor
    private func waitUntil(
        _ condition: @escaping @MainActor () -> Bool,
        timeout: TimeInterval = 2
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            guard Date() < deadline else {
                XCTFail("Timed out waiting for PodPinStore")
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}

private actor ItemRefreshGate {
    private let blockedFolderID: UUID
    private var didBlock = false
    private var blockWaiters: [CheckedContinuation<Void, Never>] = []
    private var blockedRefreshContinuation: CheckedContinuation<Void, Never>?
    private var completedFolderKeys: Set<String> = []
    private var completionWaiters: [String: [CheckedContinuation<Void, Never>]] = [:]

    init(blockedFolderID: UUID) {
        self.blockedFolderID = blockedFolderID
    }

    func blockIfNeeded(_ folderID: UUID) async {
        guard folderID == blockedFolderID else { return }
        didBlock = true
        let waiters = blockWaiters
        blockWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
        await withCheckedContinuation { continuation in
            blockedRefreshContinuation = continuation
        }
    }

    func waitUntilBlocked() async {
        guard !didBlock else { return }
        await withCheckedContinuation { continuation in
            blockWaiters.append(continuation)
        }
    }

    func releaseBlockedRefresh() {
        blockedRefreshContinuation?.resume()
        blockedRefreshContinuation = nil
    }

    func recordCompletion(for folderID: UUID) {
        let key = key(for: folderID)
        completedFolderKeys.insert(key)
        let waiters = completionWaiters.removeValue(forKey: key) ?? []
        for waiter in waiters {
            waiter.resume()
        }
    }

    func waitUntilCompleted(for folderID: UUID) async {
        let key = key(for: folderID)
        guard !completedFolderKeys.contains(key) else { return }
        await withCheckedContinuation { continuation in
            completionWaiters[key, default: []].append(continuation)
        }
    }

    private func key(for folderID: UUID) -> String {
        folderID.uuidString
    }
}

private actor CompletionProbe {
    private var completed = false

    func markCompleted() {
        completed = true
    }

    func isCompleted() -> Bool {
        completed
    }
}

private final class SynchronousFactoryGate: @unchecked Sendable {
    private let blocked = DispatchSemaphore(value: 0)
    private let releaseSemaphore = DispatchSemaphore(value: 0)

    func block() {
        blocked.signal()
        releaseSemaphore.wait()
    }

    func waitUntilBlocked() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async { [blocked] in
                blocked.wait()
                continuation.resume()
            }
        }
    }

    func release() {
        releaseSemaphore.signal()
    }
}

private actor LibraryOperationGate {
    private var isBlocked = false
    private var blockedWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    func block() async {
        isBlocked = true
        let waiters = blockedWaiters
        blockedWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
        await withCheckedContinuation { continuation in
            releaseContinuation = continuation
        }
    }

    func waitUntilBlocked() async {
        guard !isBlocked else { return }
        await withCheckedContinuation { continuation in
            blockedWaiters.append(continuation)
        }
    }

    func release() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

private actor CountingStreamImporter: ContentImporting {
    private var resolutions = 0
    private var resolutionWaiters: [Int: [CheckedContinuation<Void, Never>]] = [:]

    func probe(url: URL, attempt: ImportAttempt) async throws -> ImportDiscovery {
        throw ContentImportError.unsupportedURL
    }

    func resolveStream(
        for content: ImportedAudioMetadata,
        attempt: ImportAttempt
    ) async throws -> ResolvedAudioStream {
        resolutions += 1
        let completedTargets = resolutionWaiters.keys.filter { $0 <= resolutions }
        for target in completedTargets {
            let waiters = resolutionWaiters.removeValue(forKey: target) ?? []
            for waiter in waiters {
                waiter.resume()
            }
        }
        return ResolvedAudioStream(
            url: URL(string: "https://example.invalid/audio-\(resolutions).m4a")!,
            headers: [:],
            duration: content.duration
        )
    }

    func download(
        content: ImportedAudioMetadata,
        to destinationDirectory: URL,
        attempt: ImportAttempt,
        progress: @escaping @Sendable (DownloadProgressSnapshot) -> Void
    ) async throws -> DownloadedAudioFile {
        throw ContentImportError.mediaUnavailable("Download is not used by this test.")
    }

    func waitUntilResolutionCount(_ target: Int) async {
        guard resolutions < target else { return }
        await withCheckedContinuation { continuation in
            resolutionWaiters[target, default: []].append(continuation)
        }
    }

    func resolutionCount() -> Int {
        resolutions
    }
}

private actor DelayedFirstStreamImporter: ContentImporting {
    private var firstResolutionStarted = false
    private var firstResolutionStartWaiters: [CheckedContinuation<Void, Never>] = []
    private var firstResolutionRelease: CheckedContinuation<Void, Never>?

    func probe(url: URL, attempt: ImportAttempt) async throws -> ImportDiscovery {
        throw ContentImportError.unsupportedURL
    }

    func resolveStream(
        for content: ImportedAudioMetadata,
        attempt: ImportAttempt
    ) async throws -> ResolvedAudioStream {
        if content.contentID == "video-a" {
            firstResolutionStarted = true
            let waiters = firstResolutionStartWaiters
            firstResolutionStartWaiters.removeAll()
            for waiter in waiters {
                waiter.resume()
            }
            await withCheckedContinuation { continuation in
                firstResolutionRelease = continuation
            }
        }

        return ResolvedAudioStream(
            url: URL(fileURLWithPath: "/dev/null"),
            headers: [:],
            duration: content.duration
        )
    }

    func download(
        content: ImportedAudioMetadata,
        to destinationDirectory: URL,
        attempt: ImportAttempt,
        progress: @escaping @Sendable (DownloadProgressSnapshot) -> Void
    ) async throws -> DownloadedAudioFile {
        throw ContentImportError.mediaUnavailable("Download is not used by this test.")
    }

    func waitUntilFirstResolutionStarts() async {
        guard !firstResolutionStarted else { return }
        await withCheckedContinuation { continuation in
            firstResolutionStartWaiters.append(continuation)
        }
    }

    func releaseFirstResolution() {
        firstResolutionRelease?.resume()
        firstResolutionRelease = nil
    }
}

private actor CapturingProbeImporter: ContentImporting {
    private(set) var probedURLs: [URL] = []

    func probe(url: URL, attempt: ImportAttempt) async throws -> ImportDiscovery {
        probedURLs.append(url)
        let metadata = ImportedAudioMetadata(
            platform: .douyin,
            contentID: "share-phrase",
            sourceURL: url,
            title: "分享内容",
            author: nil,
            artworkURL: nil,
            duration: nil
        )
        return ImportDiscovery(sourceURL: url, primaryItem: metadata)
    }

    func allProbedURLs() -> [URL] {
        probedURLs
    }

    func resolveStream(
        for content: ImportedAudioMetadata,
        attempt: ImportAttempt
    ) async throws -> ResolvedAudioStream {
        throw ContentImportError.mediaUnavailable("The test only probes metadata.")
    }

    func download(
        content: ImportedAudioMetadata,
        to destinationDirectory: URL,
        attempt: ImportAttempt,
        progress: @escaping @Sendable (DownloadProgressSnapshot) -> Void
    ) async throws -> DownloadedAudioFile {
        throw ContentImportError.mediaUnavailable("The test only probes metadata.")
    }
}

private actor VerificationThenSuccessImporter: ContentImporting {
    private var attempts = 0

    func probe(url: URL, attempt: ImportAttempt) async throws -> ImportDiscovery {
        attempts += 1
        if attempts == 1 {
            throw ContentImportError.browserAccessRequired(
                PlatformVerificationRequest(source: .douyin, url: url)
            )
        }
        let metadata = ImportedAudioMetadata(
            platform: .douyin,
            contentID: "verified",
            sourceURL: url,
            title: "已验证的内容",
            author: nil,
            artworkURL: nil,
            duration: nil
        )
        return ImportDiscovery(sourceURL: url, primaryItem: metadata)
    }

    func resolveStream(
        for content: ImportedAudioMetadata,
        attempt: ImportAttempt
    ) async throws -> ResolvedAudioStream {
        throw ContentImportError.mediaUnavailable("The test only probes metadata.")
    }

    func download(
        content: ImportedAudioMetadata,
        to destinationDirectory: URL,
        attempt: ImportAttempt,
        progress: @escaping @Sendable (DownloadProgressSnapshot) -> Void
    ) async throws -> DownloadedAudioFile {
        throw ContentImportError.mediaUnavailable("The test only probes metadata.")
    }

    func probeCount() -> Int {
        attempts
    }
}

private actor VerificationThenStreamImporter: ContentImporting {
    private var resolutions = 0

    func probe(url: URL, attempt: ImportAttempt) async throws -> ImportDiscovery {
        throw ContentImportError.unsupportedURL
    }

    func resolveStream(
        for content: ImportedAudioMetadata,
        attempt: ImportAttempt
    ) async throws -> ResolvedAudioStream {
        resolutions += 1
        if resolutions == 1 {
            throw ContentImportError.browserAccessRequired(
                PlatformVerificationRequest(source: .douyin, url: content.sourceURL)
            )
        }
        return ResolvedAudioStream(
            url: URL(fileURLWithPath: "/dev/null"),
            headers: [:],
            duration: content.duration
        )
    }

    func download(
        content: ImportedAudioMetadata,
        to destinationDirectory: URL,
        attempt: ImportAttempt,
        progress: @escaping @Sendable (DownloadProgressSnapshot) -> Void
    ) async throws -> DownloadedAudioFile {
        throw ContentImportError.mediaUnavailable("The test only resolves a stream.")
    }

    func resolutionCount() -> Int {
        resolutions
    }
}

private actor GatedDownloadImporter: ContentImporting {
    private struct DownloadKey: Hashable, Sendable {
        let contentID: String
        let attempt: Int
    }

    private enum Outcome: Sendable {
        case failure
        case success
    }

    private var attemptsByContentID: [String: Int] = [:]
    private var startedDownloads: Set<DownloadKey> = []
    private var startWaiters: [DownloadKey: [CheckedContinuation<Void, Never>]] = [:]
    private var pendingDownloads: [DownloadKey: CheckedContinuation<Outcome, Never>] = [:]
    private var progressHandlers: [DownloadKey: @Sendable (DownloadProgressSnapshot) -> Void] = [:]

    func probe(url: URL, attempt: ImportAttempt) async throws -> ImportDiscovery {
        throw ContentImportError.unsupportedURL
    }

    func resolveStream(
        for content: ImportedAudioMetadata,
        attempt: ImportAttempt
    ) async throws -> ResolvedAudioStream {
        throw ContentImportError.mediaUnavailable("Streaming is not used by this test.")
    }

    func download(
        content: ImportedAudioMetadata,
        to destinationDirectory: URL,
        attempt importAttempt: ImportAttempt,
        progress: @escaping @Sendable (DownloadProgressSnapshot) -> Void
    ) async throws -> DownloadedAudioFile {
        let attempt = (attemptsByContentID[content.contentID] ?? 0) + 1
        attemptsByContentID[content.contentID] = attempt
        let key = DownloadKey(contentID: content.contentID, attempt: attempt)
        progressHandlers[key] = progress
        let outcome = await withCheckedContinuation { continuation in
            pendingDownloads[key] = continuation
            startedDownloads.insert(key)
            let waiters = startWaiters.removeValue(forKey: key) ?? []
            for waiter in waiters {
                waiter.resume()
            }
        }

        switch outcome {
        case .failure:
            throw ContentImportError.externalToolFailed("Intentional test failure")
        case .success:
            let audioURL = destinationDirectory.appendingPathComponent("audio.m4a")
            try Data([0]).write(to: audioURL, options: .atomic)
            return DownloadedAudioFile(url: audioURL, duration: 1)
        }
    }

    func waitUntilDownloadStarts(contentID: String, attempt: Int) async {
        let key = DownloadKey(contentID: contentID, attempt: attempt)
        guard !startedDownloads.contains(key) else { return }
        await withCheckedContinuation { continuation in
            startWaiters[key, default: []].append(continuation)
        }
    }

    func downloadAttempts(for contentID: String) -> Int {
        attemptsByContentID[contentID, default: 0]
    }

    func failDownload(contentID: String, attempt: Int) {
        finishDownload(
            DownloadKey(contentID: contentID, attempt: attempt),
            with: .failure
        )
    }

    func succeedDownload(contentID: String, attempt: Int) {
        finishDownload(
            DownloadKey(contentID: contentID, attempt: attempt),
            with: .success
        )
    }

    func reportProgress(_ progress: DownloadProgressSnapshot, contentID: String, attempt: Int) {
        progressHandlers[DownloadKey(contentID: contentID, attempt: attempt)]?(progress)
    }

    private func finishDownload(_ key: DownloadKey, with outcome: Outcome) {
        progressHandlers.removeValue(forKey: key)
        pendingDownloads.removeValue(forKey: key)?.resume(returning: outcome)
    }
}

private actor CancellableDownloadImporter: ContentImporting {
    private var attemptsByContentID: [String: Int] = [:]
    private var firstDownloadStarted = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []

    func probe(url: URL, attempt: ImportAttempt) async throws -> ImportDiscovery {
        throw ContentImportError.unsupportedURL
    }

    func resolveStream(
        for content: ImportedAudioMetadata,
        attempt: ImportAttempt
    ) async throws -> ResolvedAudioStream {
        throw ContentImportError.mediaUnavailable("Streaming is not used by this test.")
    }

    func download(
        content: ImportedAudioMetadata,
        to destinationDirectory: URL,
        attempt: ImportAttempt,
        progress: @escaping @Sendable (DownloadProgressSnapshot) -> Void
    ) async throws -> DownloadedAudioFile {
        attemptsByContentID[content.contentID, default: 0] += 1
        if !firstDownloadStarted {
            firstDownloadStarted = true
            let waiters = startWaiters
            startWaiters.removeAll()
            for waiter in waiters {
                waiter.resume()
            }
        }
        try await Task.sleep(for: .seconds(60))
        throw ContentImportError.mediaUnavailable("The test expected cancellation.")
    }

    func waitUntilFirstDownloadStarts() async {
        guard !firstDownloadStarted else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func downloadAttempts(for contentID: String) -> Int {
        attemptsByContentID[contentID, default: 0]
    }
}

private actor ExplicitBrowserRetryImporter: ContentImporting {
    private var retries = 0

    func probe(url: URL, attempt: ImportAttempt) async throws -> ImportDiscovery {
        switch attempt {
        case .anonymous:
            throw ContentImportError.browserAccessRequired(
                PlatformVerificationRequest(source: .douyin, url: url)
            )
        case .browserRetry:
            retries += 1
            let canonical = URL(string: "https://www.douyin.com/video/7667887133545205043")!
            return ImportDiscovery(
                sourceURL: canonical,
                primaryItem: ImportedAudioMetadata(
                    platform: .douyin,
                    contentID: "7667887133545205043",
                    sourceURL: canonical,
                    title: "Public video",
                    author: "Author",
                    artworkURL: nil,
                    duration: 1
                )
            )
        }
    }

    func resolveStream(
        for content: ImportedAudioMetadata,
        attempt: ImportAttempt
    ) async throws -> ResolvedAudioStream {
        throw ContentImportError.mediaUnavailable("Not used")
    }

    func download(
        content: ImportedAudioMetadata,
        to destinationDirectory: URL,
        attempt: ImportAttempt,
        progress: @escaping @Sendable (DownloadProgressSnapshot) -> Void
    ) async throws -> DownloadedAudioFile {
        throw ContentImportError.mediaUnavailable("Not used")
    }

    func browserRetryCount() -> Int { retries }
}

private actor StubBrowserAccessAuthorizer: BrowserAccessAuthorizing {
    let profile: BrowserProfile

    init(profile: BrowserProfile) {
        self.profile = profile
    }

    func profiles() async -> [BrowserProfile] { [profile] }

    func authorize(
        profile: BrowserProfile,
        request: PlatformVerificationRequest,
        contentIDs: Set<String>
    ) async throws -> BrowserAccessLease {
        BrowserAccessLease(
            source: request.source,
            sourceURL: request.url,
            contentIDs: contentIDs,
            expiresAt: Date().addingTimeInterval(60),
            cookies: []
        )
    }

    func revoke(_ lease: BrowserAccessLease) async {
        lease.revoke()
    }
}

private actor DelayedBrowserAccessAuthorizer: BrowserAccessAuthorizing {
    let profile: BrowserProfile
    private let lease: BrowserAccessLease
    private var didStart = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var authorizationContinuation: CheckedContinuation<Void, Never>?

    init(profile: BrowserProfile, sourceURL: URL) {
        self.profile = profile
        lease = BrowserAccessLease(
            source: .douyin,
            sourceURL: sourceURL,
            contentIDs: [],
            expiresAt: Date().addingTimeInterval(60),
            cookies: []
        )
    }

    func profiles() async -> [BrowserProfile] { [profile] }

    func authorize(
        profile: BrowserProfile,
        request: PlatformVerificationRequest,
        contentIDs: Set<String>
    ) async throws -> BrowserAccessLease {
        didStart = true
        let waiters = startWaiters
        startWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
        await withCheckedContinuation { continuation in
            authorizationContinuation = continuation
        }
        return lease
    }

    func revoke(_ lease: BrowserAccessLease) async {
        lease.revoke()
    }

    func waitUntilAuthorizationStarts() async {
        guard !didStart else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func releaseAuthorization() {
        authorizationContinuation?.resume()
        authorizationContinuation = nil
    }

    func leaseWasRevoked() -> Bool {
        !lease.consume(source: .douyin, url: lease.sourceURL, contentID: nil)
    }
}

private final class ThreadRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Bool] = []

    func recordCurrentThread() {
        lock.lock()
        values.append(Thread.isMainThread)
        lock.unlock()
    }

    func mainThreadValues() -> [Bool] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }
}
