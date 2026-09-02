import Combine
import Foundation
import OSLog

enum LibraryStartupPhase: Equatable {
    case loading
    case ready
    case failed(String)
}

enum LibraryItemsPhase: Equatable {
    case idle
    case loading(LibraryCollection)
    case loaded(LibraryCollection)
    case empty(LibraryCollection)
    case failed(LibraryCollection, PresentedError)
}

@MainActor
final class PodPinStore: ObservableObject {
    private static let performanceSignposter = OSSignposter(
        subsystem: "io.github.cmy-hhxx.podpin",
        category: "library.performance"
    )
    private static let playbackPerformanceSignposter = OSSignposter(
        subsystem: "io.github.cmy-hhxx.podpin",
        category: "playback.performance"
    )

    enum ImportChoice: Sendable {
        case stream
        case download
    }

    private enum VerificationOperation {
        case probe(URL)
        case play(AudioItem)
        case queuedPlayback(AudioItem)
        case download(AudioItem)
    }

    let librarySession = LibrarySession()
    let importSession = ImportSession()
    let downloadSession = DownloadSession()

    var folders: [LibraryFolder] {
        get { librarySession.folders }
        set { librarySession.folders = newValue }
    }
    var selectedCollection: LibraryCollection {
        get { librarySession.selectedCollection }
        set { selectCollection(newValue) }
    }
    /// Transitional convenience for import and folder-management flows. Smart
    /// collections deliberately resolve imports to the system inbox.
    var selectedFolderID: UUID {
        get { librarySession.selectedCollection.defaultImportFolderID }
        set { selectCollection(.folder(newValue)) }
    }
    var items: [AudioItem] {
        get { librarySession.items }
        set { librarySession.items = newValue }
    }
    var canLoadMoreItems: Bool {
        get { librarySession.canLoadMoreItems }
        set { librarySession.canLoadMoreItems = newValue }
    }
    @Published private(set) var currentItem: AudioItem?
    @Published private(set) var currentPlaybackPhase: PlaybackPhase = .idle
    var isStarting: Bool {
        get { librarySession.isStarting }
        set { librarySession.isStarting = newValue }
    }
    var startupError: String? {
        get { librarySession.startupError }
        set { librarySession.startupError = newValue }
    }
    var startupPhase: LibraryStartupPhase {
        get { librarySession.startupPhase }
        set { librarySession.startupPhase = newValue }
    }
    var itemsPhase: LibraryItemsPhase {
        get { librarySession.itemsPhase }
        set { librarySession.itemsPhase = newValue }
    }
    @Published private(set) var activityMessage: String?
    var activeDownloadItemID: UUID? {
        get { downloadSession.activeItemID }
        set { downloadSession.activeItemID = newValue }
    }
    /// High-frequency progress is published only by `DownloadSession`, keeping
    /// the broader library and playback stores out of the network tick path.
    private var activeDownloadProgress: DownloadProgressSnapshot {
        get { downloadSession.snapshot }
        set { downloadSession.update(newValue) }
    }
    var verificationRequest: PlatformVerificationRequest? {
        get { importSession.verificationRequest }
        set { importSession.verificationRequest = newValue }
    }
    var browserProfiles: [BrowserProfile] {
        get { importSession.browserProfiles }
        set { importSession.browserProfiles = newValue }
    }
    var hasRequestedBrowserProfiles: Bool {
        get { importSession.hasRequestedBrowserProfiles }
        set { importSession.hasRequestedBrowserProfiles = newValue }
    }
    var isDiscoveringBrowserProfiles: Bool {
        get { importSession.isDiscoveringBrowserProfiles }
        set { importSession.isDiscoveringBrowserProfiles = newValue }
    }
    var importIssue: PresentedError? {
        get { importSession.issue }
        set { importSession.issue = newValue }
    }
    @Published var userFacingError: PresentedError?

    let preferences: AppPreferences
    let playbackPresentation = PlaybackPresentationModel()
    let playbackQueue = PlaybackQueueController()

    /// Compatibility accessors for low-frequency library surfaces. Live
    /// playback views should observe `playbackPresentation` directly.
    var isPlaying: Bool { currentPlaybackPhase.isPlaying }
    var currentTime: TimeInterval { playbackPresentation.snapshot.currentTime }
    var currentDuration: TimeInterval { playbackPresentation.snapshot.duration }
    var playbackPhase: PlaybackPhase { currentPlaybackPhase }

    private let databaseFactory: @Sendable () throws -> MarketDatabase
    private let mediaStoreFactory: @Sendable () throws -> PodPinMediaStore
    private let importer: any ContentImporting
    private let resolvedStreamCache: ResolvedAudioStreamCache
    private let artworkDownloader: any ArtworkCaching
    private let playbackController: AudioPlaybackController
    private let nowPlayingController: NowPlayingController
    private let browserAccessAuthorizer: any BrowserAccessAuthorizing
    private var database: MarketDatabase?
    private var mediaStore: PodPinMediaStore?
    private var isStarted = false
    private var isShutDown = false
    private var playbackRequestGeneration: UInt = 0
    private var itemRefreshGeneration: UInt = 0
    private var startupTask: Task<Void, Never>?
    private var itemRefreshTask: Task<Void, Never>?
    private var itemLoadMoreTask: Task<Void, Never>?
    private var browserProfileTask: Task<Void, Never>?
    private var nextItemCursor: ItemCursor?
    private var isLoadingMoreItems = false
    private var cachedFolderTree: [LibraryFolderNode] = []
    private var cachedVisibleItems: [LibraryItemRow] = []
    private var activeDownloadTask: Task<Void, Never>?
    private var verificationOperation: VerificationOperation?
    private var pendingBrowserLease: BrowserAccessLease?
    private var playbackRecoveryAttempts = Set<UUID>()
    private var pendingQueueConsumptionItemID: UUID?
    /// Keeps the focused player responsive while an online source is being
    /// resolved. The actual player remains untouched until a usable stream
    /// URL arrives, so a failed request can fall back to the prior item.
    private var resolvingPlaybackItem: AudioItem?
    private var artworkTasks: [UUID: Task<Void, Never>] = [:]
    private var artworkTaskTokens: [UUID: UUID] = [:]
    private var ownedTasks: [UUID: Task<Void, Never>] = [:]
    private var ownedTaskTimeouts: [UUID: Task<Void, Never>] = [:]
    private var lastNowPlayingIdentity: NowPlayingIdentity?
    private var needsNowPlayingTimeSync = true

    #if DEBUG || PODPIN_TESTING
        var hasPendingBrowserAccess: Bool { pendingBrowserLease != nil }
        var itemRefreshTestHook: ((LibraryCollection) async -> Void)?
        var itemRefreshCompletionTestHook: ((LibraryCollection) -> Void)?
    #endif

    init(
        preferences: AppPreferences,
        databaseFactory: @escaping @Sendable () throws -> MarketDatabase = {
            try MarketDatabase.openInApplicationSupport()
        },
        mediaStoreFactory: @escaping @Sendable () throws -> PodPinMediaStore = {
            try PodPinMediaStore.inApplicationSupport()
        },
        importer: (any ContentImporting)? = nil,
        resolvedStreamCache: ResolvedAudioStreamCache = ResolvedAudioStreamCache(),
        artworkDownloader: any ArtworkCaching = ArtworkDownloader(),
        browserAccessAuthorizer: any BrowserAccessAuthorizing = BrowserAccessBroker(),
        playbackController: AudioPlaybackController = AudioPlaybackController(),
        nowPlayingController: NowPlayingController = NowPlayingController()
    ) {
        self.preferences = preferences
        self.databaseFactory = databaseFactory
        self.mediaStoreFactory = mediaStoreFactory
        self.resolvedStreamCache = resolvedStreamCache
        self.artworkDownloader = artworkDownloader
        self.browserAccessAuthorizer = browserAccessAuthorizer
        self.playbackController = playbackController
        self.nowPlayingController = nowPlayingController

        self.importer = importer ?? PodPinContentImporter()

        playbackController.onPlaybackPositionChanged = {
            [weak self] id, position, listeningHistory, force in
            guard let self else { return }
            self.persistPlaybackPosition(
                id: id,
                position: position,
                listeningHistory: listeningHistory,
                force: force
            )
        }
        playbackController.onStateChanged = { [weak self] in
            self?.synchronizePlaybackPresentation()
        }
        playbackController.onOutputChanged = { [weak self] in
            self?.synchronizePlaybackPresentation()
        }
        playbackController.onPlaybackReady = { [weak self] itemID in
            guard let self else { return }
            self.launchOwnedTask { [weak self] in
                await self?.consumeReadyQueueItemIfNeeded(itemID)
            }
        }
        playbackController.onPlaybackFinished = { [weak self] itemID in
            guard let self else { return }
            self.launchOwnedTask { [weak self] in
                await self?.advancePlaybackQueue(after: itemID)
            }
        }
        playbackController.onPlaybackFailed = { [weak self] itemID, message, statusCode in
            guard let self else { return }
            self.launchOwnedTask { [weak self] in
                await self?.handlePlaybackFailure(
                    itemID: itemID, message: message, statusCode: statusCode)
            }
        }
        nowPlayingController.onTogglePlayback = { [weak self] in self?.togglePlayback() }
        nowPlayingController.onPlay = { [weak self] in self?.resumePlayback() }
        nowPlayingController.onPause = { [weak self] in self?.pausePlayback() }
        nowPlayingController.onSkipBackward = { [weak self] in self?.skipBackward() }
        nowPlayingController.onSkipForward = { [weak self] in self?.skipForward() }
        nowPlayingController.onSeek = { [weak self] in self?.seek(to: $0) }
        nowPlayingController.onChangeRate = { [weak self] in self?.setPlaybackRate($0) }
    }

    private nonisolated static func openPersistenceResources(
        databaseFactory: @escaping @Sendable () throws -> MarketDatabase,
        mediaStoreFactory: @escaping @Sendable () throws -> PodPinMediaStore
    ) async throws -> (database: MarketDatabase, mediaStore: PodPinMediaStore) {
        try Task.checkCancellation()
        let database = try databaseFactory()
        try Task.checkCancellation()
        let mediaStore = try mediaStoreFactory()
        try Task.checkCancellation()
        return (database, mediaStore)
    }

    func resumeUI() async {
        guard !isShutDown else { return }
        nowPlayingController.activate()
        if isStarted {
            await refreshItems()
        } else {
            await start()
        }
    }

    func start() async {
        if let startupTask {
            await withTaskCancellationHandler {
                await startupTask.value
            } onCancel: {
                startupTask.cancel()
            }
            return
        }
        guard !isShutDown, !isStarted, !isStarting else { return }

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performStart()
        }
        startupTask = task
        await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
        startupTask = nil
    }

    private func performStart() async {
        guard !isShutDown, !isStarted, !isStarting else { return }
        nowPlayingController.activate()
        isStarting = true
        startupError = nil
        startupPhase = .loading
        defer { isStarting = false }

        do {
            let resources = try await Self.openPersistenceResources(
                databaseFactory: databaseFactory,
                mediaStoreFactory: mediaStoreFactory
            )
            try Task.checkCancellation()
            let database = resources.database
            let mediaStore = resources.mediaStore
            self.database = database
            self.mediaStore = mediaStore
            playbackQueue.configure(repository: database)
            let interruptedDownloads = try await database.recoverInterruptedDownloads()
            try Task.checkCancellation()
            guard !isShutDown else { return }
            for itemID in interruptedDownloads {
                do {
                    try await mediaStore.removeDownloadedAudio(for: itemID)
                } catch {
                    // Recovery continues so a stale artifact cannot block the
                    // database repair; the cleanup failure remains observable.
                    await AppDiagnostics.shared.record(
                        level: .warning, category: "storage",
                        event: "interrupted-download.cleanup.failed",
                        error: PresentedError.from(error))
                }
            }
            try Task.checkCancellation()
            guard !isShutDown else { return }
            isStarted = true
            try await playbackQueue.reload()
            try Task.checkCancellation()
            guard !isShutDown else { return }
            let refreshedFolders = try await database.allFolders()
            try Task.checkCancellation()
            guard !isShutDown else { return }
            cachedFolderTree = makeFolderTree(from: refreshedFolders)
            folders = refreshedFolders
            librarySession.selectedCollection = preferences.lastLibraryCollection
            if case .folder(let folderID) = selectedCollection,
                !folders.contains(where: { $0.id == folderID })
            {
                librarySession.selectedCollection = .recentlyImported
                preferences.lastLibraryCollection = .recentlyImported
            }
            try await refreshItemsOrThrow(for: itemRefreshRequest())
            try Task.checkCancellation()
            guard !isShutDown else { return }
            replaceCurrentItemIfNeeded(try await database.currentPlaybackItem())
            try Task.checkCancellation()
            guard !isShutDown else { return }
            if let currentItem,
                currentItem.storageKind == .offline
            {
                let containsLocalMedia =
                    if let relativePath = currentItem.localMediaRelativePath {
                        await mediaStore.containsFile(at: relativePath)
                    } else {
                        false
                    }
                if !containsLocalMedia {
                    _ = try await database.updateDownloadState(for: currentItem.id, state: .failed)
                    try Task.checkCancellation()
                    guard !isShutDown else { return }
                    replaceCurrentItemIfNeeded(try await database.item(id: currentItem.id))
                    try Task.checkCancellation()
                    guard !isShutDown else { return }
                }
            }
            // A crash can occur after persisting the replacement current item
            // but before AVFoundation reports it ready. On the next launch it
            // is current, not upcoming, so repair that narrow transient state.
            if let currentItem,
                playbackQueue.session.entries.contains(where: { $0.item.id == currentItem.id })
            {
                try await playbackQueue.remove(currentItem.id)
                try Task.checkCancellation()
                guard !isShutDown else { return }
            }
            playbackController.setRate(preferences.playbackRate)
            playbackController.setVolume(preferences.playbackVolume)
            synchronizePlaybackPresentation()
            startupPhase = .ready
        } catch {
            isStarted = false
            if isShutDown || isCancellation(error) {
                database = nil
                mediaStore = nil
                return
            }
            database = nil
            mediaStore = nil
            startupError = error.localizedDescription
            startupPhase = .failed(error.localizedDescription)
        }
    }

    func retryStart() async {
        isStarted = false
        await start()
    }

    /// Releases work that only serves the visible tool surface. Playback,
    /// remote commands, and downloads explicitly started by the user continue
    /// while another OneBox tool is selected.
    func suspendUI() {
        itemRefreshGeneration &+= 1
        itemRefreshTask?.cancel()
        itemRefreshTask = nil
        itemLoadMoreTask?.cancel()
        itemLoadMoreTask = nil
        isLoadingMoreItems = false
        browserProfileTask?.cancel()
        browserProfileTask = nil
        cancelVerification()
        discardPendingBrowserAccess()
        for task in artworkTasks.values {
            task.cancel()
        }
        artworkTasks.removeAll()
        artworkTaskTokens.removeAll()
    }

    /// Terminates the long-lived module session. The host must await this at
    /// application shutdown; hiding the tool calls `suspendUI()` instead.
    func shutdown() async {
        guard !isShutDown else { return }
        isShutDown = true
        isStarted = false
        playbackRequestGeneration &+= 1

        let startupTask = self.startupTask
        let transientTasks = [itemRefreshTask, itemLoadMoreTask, browserProfileTask]
            .compactMap { $0 }
        let pendingArtworkTasks = Array(artworkTasks.values)
        let downloadTask = activeDownloadTask
        let pendingOwnedTasks = Array(ownedTasks.values)
        let pendingOwnedTaskTimeouts = Array(ownedTaskTimeouts.values)
        suspendUI()
        startupTask?.cancel()
        downloadTask?.cancel()
        for task in pendingOwnedTasks {
            task.cancel()
        }
        for timeoutTask in pendingOwnedTaskTimeouts {
            timeoutTask.cancel()
        }

        if let startupTask {
            await startupTask.value
        }
        self.startupTask = nil
        for task in transientTasks {
            await task.value
        }
        for task in pendingArtworkTasks {
            await task.value
        }
        if let downloadTask {
            await downloadTask.value
        }
        for task in pendingOwnedTasks {
            await task.value
        }
        for timeoutTask in pendingOwnedTaskTimeouts {
            await timeoutTask.value
        }
        ownedTasks.removeAll()
        ownedTaskTimeouts.removeAll()

        playbackController.flushPlaybackPosition()
        let database = self.database
        let playbackItem = playbackController.currentItem
        let playbackPosition = playbackController.currentTime
        let listeningHistory = playbackController.listeningHistory
        playbackController.stop()
        await nowPlayingController.deactivate()
        lastNowPlayingIdentity = nil
        needsNowPlayingTimeSync = true

        if let database, let playbackItem {
            do {
                _ = try await database.updatePlaybackPosition(
                    for: playbackItem.id,
                    position: playbackPosition,
                    listeningHistory: listeningHistory
                )
            } catch {
                await AppDiagnostics.shared.record(
                    level: .warning,
                    category: "playback",
                    event: "shutdown.position.flush.failed",
                    error: PresentedError.from(error)
                )
            }
        }

        activeDownloadTask = nil
        activeDownloadItemID = nil
        activeDownloadProgress = .indeterminate
        self.database = nil
        mediaStore = nil
    }

    private func selectCollection(_ collection: LibraryCollection) {
        guard collection != librarySession.selectedCollection else { return }
        librarySession.selectedCollection = collection
        preferences.lastLibraryCollection = collection
        itemRefreshGeneration &+= 1
        beginLoadingItems(for: collection)
        let request = itemRefreshRequest()
        itemRefreshTask?.cancel()
        itemRefreshTask = Task { [weak self] in
            await self?.refreshItems(for: request)
        }
    }

    func retrySelectedFolder() {
        itemRefreshGeneration &+= 1
        beginLoadingItems(for: selectedCollection)
        let request = itemRefreshRequest()
        itemRefreshTask?.cancel()
        itemRefreshTask = Task { [weak self] in
            await self?.refreshItems(for: request)
        }
    }

    func dismissError() {
        userFacingError = nil
    }

    func dismissImportIssue() {
        importIssue = nil
    }

    func folderTree() -> [LibraryFolderNode] {
        cachedFolderTree
    }

    private func makeFolderTree(from folders: [LibraryFolder]) -> [LibraryFolderNode] {
        let foldersByID = Dictionary(uniqueKeysWithValues: folders.map { ($0.id, $0) })
        let childrenByParent = Dictionary(grouping: folders, by: \.parentID)
        var depthCache: [UUID: Int] = [:]

        func depth(of folder: LibraryFolder) -> Int {
            if let cached = depthCache[folder.id] { return cached }
            var current = folder.parentID
            var visited: Set<UUID> = [folder.id]
            var depth = 0
            while let parentID = current,
                let parent = foldersByID[parentID],
                visited.insert(parentID).inserted
            {
                depth += 1
                current = parent.parentID
            }
            depthCache[folder.id] = depth
            return depth
        }

        var nodesByID: [UUID: LibraryFolderNode] = [:]
        for folder in folders.sorted(by: { depth(of: $0) > depth(of: $1) }) {
            let children = (childrenByParent[folder.id] ?? []).compactMap { nodesByID[$0.id] }
            nodesByID[folder.id] = LibraryFolderNode(
                id: folder.id,
                name: folder.displayName,
                isSystemFolder: folder.isSystemFolder,
                children: children
            )
        }
        return (childrenByParent[nil] ?? []).compactMap { nodesByID[$0.id] }
    }

    func selectedFolderTitle() -> String? {
        switch selectedCollection {
        case .recentlyImported, .recentlyPlayed, .downloaded:
            selectedCollection.title
        case .folder(let folderID):
            folders.first(where: { $0.id == folderID })?.displayName
        }
    }

    func visibleItems() -> [LibraryItemRow] {
        cachedVisibleItems
    }

    private func makeVisibleItems(from items: [AudioItem]) -> [LibraryItemRow] {
        items.map { item in
            LibraryItemRow(
                id: item.id,
                folderID: item.folderID,
                title: item.title,
                author: item.author,
                sourceName: sourceName(for: item.platform),
                duration: item.duration,
                importedAt: item.importedAt,
                storageState: libraryStorageState(for: item),
                progress: item.playbackPosition,
                listeningHistory: item.listeningHistory,
                artworkURL: absoluteArtworkURL(for: item)
            )
        }
    }

    @discardableResult
    func createFolderOrThrow(named name: String, parentID: UUID?) async throws -> LibraryFolder {
        let operationID = UUID()
        let interval = Self.performanceSignposter.beginInterval("folder.create")
        defer { Self.performanceSignposter.endInterval("folder.create", interval) }
        await AppDiagnostics.shared.record(
            category: "library", event: "folder.create.started", operationID: operationID)
        let database = try requireDatabase()
        let created = try await database.createFolder(named: name, parentID: parentID)
        await refreshFolders()
        await AppDiagnostics.shared.record(
            category: "library", event: "folder.create.finished", operationID: operationID)
        return created
    }

    @discardableResult
    func createFolder(
        named name: String,
        parentID: UUID?,
        reportError: Bool = true
    ) async -> LibraryFolder? {
        do {
            let created = try await createFolderOrThrow(named: name, parentID: parentID)
            return created
        } catch {
            if reportError { present(error) }
            return nil
        }
    }

    @discardableResult
    func renameFolderOrThrow(_ id: UUID, to name: String) async throws -> LibraryFolder {
        let database = try requireDatabase()
        let renamed = try await database.renameFolder(id, to: name)
        await refreshFolders()
        return renamed
    }

    @discardableResult
    func renameFolder(
        _ id: UUID,
        to name: String,
        reportError: Bool = true
    ) async -> Bool {
        do {
            _ = try await renameFolderOrThrow(id, to: name)
            return true
        } catch {
            if reportError { present(error) }
            return false
        }
    }

    func moveFolderOrThrow(_ id: UUID, to parentID: UUID?) async throws {
        let database = try requireDatabase()
        _ = try await database.moveFolder(id, toParentID: parentID)
        await refreshFolders()
    }

    func moveFolder(_ id: UUID, to parentID: UUID?) async {
        do {
            try await moveFolderOrThrow(id, to: parentID)
        } catch {
            present(error)
        }
    }

    func deleteFolderOrThrow(_ id: UUID) async throws {
        let database = try requireDatabase()
        let deletedWasSelected = selectedCollection == .folder(id)
        _ = try await database.deleteFolder(id)
        await refreshFolders()
        if deletedWasSelected { selectedCollection = .recentlyImported }
    }

    func folderDeletionReason(_ id: UUID) async -> String? {
        if folders.contains(where: { $0.parentID == id }) {
            return "请先移动或删除其中的子文件夹。"
        }
        do {
            let database = try requireDatabase()
            return try await database.listItemPage(in: id, limit: 1).items.isEmpty
                ? nil
                : "请先移动或删除其中的音频。"
        } catch {
            present(error, category: "library", event: "folder.delete.check.failed")
            return "暂时无法确认文件夹内容。"
        }
    }

    func deleteFolder(_ id: UUID) async {
        do {
            try await deleteFolderOrThrow(id)
        } catch {
            present(error)
        }
    }

    func probe(urlText: String) async -> ImportDiscovery? {
        discardPendingBrowserAccess()
        verificationRequest = nil
        verificationOperation = nil
        importIssue = nil
        let candidates = ImportLinkParser.candidates(in: urlText)
        guard candidates.urls.count == 1, let url = candidates.urls.first else {
            if candidates.urls.count > 1 {
                importIssue = .message("检测到 \(candidates.urls.count) 条可导入链接。本版一次只能导入一条，请只保留目标链接。")
            } else if candidates.detectedHTTPSURLCount > 0 {
                importIssue = .message("没有找到可导入的 B 站、抖音、小宇宙或 Fireside 公开链接。")
            } else {
                importIssue = .message("请粘贴包含 HTTPS 公开链接的分享内容。")
            }
            return nil
        }
        guard let discovery = await probe(url: url) else { return nil }
        guard discovery.primaryItem.platform == .douyin,
            discovery.primaryItem.title.hasPrefix("抖音视频 "),
            let suggestedTitle = candidates.suggestedTitle
        else { return discovery }
        let item = discovery.primaryItem
        let titledItem = ImportedAudioMetadata(
            platform: item.platform,
            contentID: item.contentID,
            sourceURL: item.sourceURL,
            title: suggestedTitle,
            author: item.author,
            artworkURL: item.artworkURL,
            duration: item.duration
        )
        return ImportDiscovery(sourceURL: discovery.sourceURL, primaryItem: titledItem)
    }

    func retryVerification() async -> ImportDiscovery? {
        guard verificationRequest != nil, let operation = verificationOperation else { return nil }
        verificationRequest = nil
        verificationOperation = nil
        switch operation {
        case .probe(let url):
            return await probe(url: url)
        case .play(let item):
            await play(item)
            return nil
        case .queuedPlayback(let item):
            await play(item, consumesQueueEntry: true)
            return nil
        case .download(let item):
            startDownload(item)
            return nil
        }
    }

    func retryBrowserAccess(using profile: BrowserProfile) async -> ImportDiscovery? {
        guard let request = verificationRequest, let operation = verificationOperation else {
            return nil
        }
        activityMessage = "正在读取所选 Profile 的访客状态…"
        defer { activityMessage = nil }
        do {
            let contentIDs: Set<String>
            switch operation {
            case .probe:
                contentIDs = []
            case .play(let item), .queuedPlayback(let item), .download(let item):
                contentIDs = [item.contentID]
            }
            let lease = try await browserAccessAuthorizer.authorize(
                profile: profile,
                request: request,
                contentIDs: contentIDs
            )
            guard !Task.isCancelled else {
                lease.revoke()
                return nil
            }
            verificationRequest = nil
            verificationOperation = nil
            browserProfiles = []
            hasRequestedBrowserProfiles = false
            isDiscoveringBrowserProfiles = false

            switch operation {
            case .probe(let url):
                do {
                    let discovery = try await importer.probe(
                        url: url,
                        attempt: .browserRetry(lease)
                    )
                    guard !Task.isCancelled else {
                        lease.revoke()
                        return nil
                    }
                    let canonicalURL = discovery.primaryItem.sourceURL
                    pendingBrowserLease?.revoke()
                    pendingBrowserLease = lease.scoped(
                        to: canonicalURL,
                        contentIDs: Set(discovery.items.map(\.contentID))
                    )
                    lease.revoke()
                    return discovery
                } catch {
                    lease.revoke()
                    throw error
                }
            case .play(let item):
                await play(item, attempt: .browserRetry(lease))
                lease.revoke()
                return nil
            case .queuedPlayback(let item):
                await play(item, attempt: .browserRetry(lease), consumesQueueEntry: true)
                lease.revoke()
                return nil
            case .download(let item):
                startDownload(
                    item,
                    attempt: .browserRetry(lease),
                    leaseToRevoke: lease
                )
                return nil
            }
        } catch {
            verificationRequest = nil
            verificationOperation = nil
            browserProfiles = []
            hasRequestedBrowserProfiles = false
            isDiscoveringBrowserProfiles = false
            present(error)
            return nil
        }
    }

    func cancelVerification() {
        browserProfileTask?.cancel()
        browserProfileTask = nil
        verificationRequest = nil
        verificationOperation = nil
        browserProfiles = []
        hasRequestedBrowserProfiles = false
        isDiscoveringBrowserProfiles = false
    }

    func discardPendingBrowserAccess() {
        pendingBrowserLease?.revoke()
        pendingBrowserLease = nil
    }

    private func probe(url: URL, attempt: ImportAttempt = .anonymous) async -> ImportDiscovery? {
        activityMessage = "正在解析链接…"
        defer { activityMessage = nil }
        do {
            return try await importer.probe(url: url, attempt: attempt)
        } catch let error as ContentImportError {
            guard !isCancellation(error) else { return nil }
            if let request = verificationRequest(from: error) {
                requireVerification(request, toRetry: .probe(url))
                return nil
            }
            importIssue = PresentedError.from(error)
            return nil
        } catch {
            guard !isCancellation(error) else { return nil }
            importIssue = PresentedError.from(error)
            return nil
        }
    }

    /// Records the item first so interrupted downloads become a clear retryable
    /// state instead of disappearing from the user's library.
    @discardableResult
    func importContent(
        _ metadata: ImportedAudioMetadata,
        into folderID: UUID,
        choice: ImportChoice
    ) async -> AudioItem? {
        do {
            try Task.checkCancellation()
            let database = try requireDatabase()
            let incoming = AudioItem(
                platform: metadata.platform,
                contentID: metadata.contentID,
                sourceURL: metadata.sourceURL,
                title: metadata.title,
                author: metadata.author,
                duration: metadata.duration,
                folderID: folderID,
                storageKind: .online,
                downloadState: .notRequested
            )
            let archive = try await database.archive(
                ArchiveRequest(items: [incoming], destinationFolderID: folderID)
            )
            let item = archive.items[0]
            selectedFolderID = archive.destinationFolderID
            await refreshItems()
            try Task.checkCancellation()

            if let artworkURL = metadata.artworkURL {
                startArtworkCaching(from: artworkURL, for: item.id)
            }

            switch choice {
            case .stream:
                await play(item)
            case .download:
                startDownload(item)
            }
            return item
        } catch {
            guard !isCancellation(error) else { return nil }
            present(error)
            return nil
        }
    }

    /// Transfers an explicit import from the transient SwiftUI surface to the
    /// module session. Shutdown cancels and drains it; normal tool switches do not.
    func startImportDiscovery(
        _ discovery: ImportDiscovery,
        selectedContentIDs: Set<String>,
        into folderID: UUID,
        choice: ImportChoice,
        completion: @escaping @MainActor @Sendable ([AudioItem]?) -> Void
    ) {
        let browserLease = pendingBrowserLease
        pendingBrowserLease = nil
        guard !isShutDown else {
            browserLease?.revoke()
            completion(nil)
            return
        }
        launchOwnedTask(timeout: .seconds(30 * 60)) { [weak self] in
            guard let self else {
                browserLease?.revoke()
                completion(nil)
                return
            }
            let saved = await self.importDiscovery(
                discovery,
                selectedContentIDs: selectedContentIDs,
                into: folderID,
                choice: choice,
                browserLease: browserLease
            )
            completion(saved)
        }
    }

    /// Archives one discovery as a single transaction. Collections stay
    /// ordered by their source, and only the selected content identities enter
    /// the in-memory sequential download queue.
    @discardableResult
    func importDiscovery(
        _ discovery: ImportDiscovery,
        selectedContentIDs: Set<String>,
        into folderID: UUID,
        choice: ImportChoice,
        browserLease: BrowserAccessLease? = nil
    ) async -> [AudioItem]? {
        var operationBrowserLease = browserLease
        defer { operationBrowserLease?.revoke() }
        let selectedMetadata = discovery.items.filter { selectedContentIDs.contains($0.contentID) }
        guard !selectedMetadata.isEmpty else {
            importIssue = .message("请至少选择一条内容。")
            return nil
        }

        do {
            try Task.checkCancellation()
            let database = try requireDatabase()
            let incoming = selectedMetadata.map { metadata in
                AudioItem(
                    platform: metadata.platform,
                    contentID: metadata.contentID,
                    sourceURL: metadata.sourceURL,
                    title: metadata.title,
                    author: metadata.author,
                    duration: metadata.duration,
                    folderID: folderID,
                    storageKind: .online,
                    downloadState: .notRequested
                )
            }
            let archive: ArchiveResult
            do {
                let interval = Self.performanceSignposter.beginInterval("archive")
                defer { Self.performanceSignposter.endInterval("archive", interval) }
                archive = try await database.archive(
                    ArchiveRequest(items: incoming, destinationFolderID: folderID)
                )
            }
            let saved = archive.items
            try Task.checkCancellation()

            for (metadata, item) in zip(selectedMetadata, saved) {
                if let artworkURL = metadata.artworkURL {
                    startArtworkCaching(from: artworkURL, for: item.id)
                }
            }

            switch choice {
            case .stream:
                if saved.count == 1, let item = saved.first {
                    if let operationBrowserLease {
                        await play(item, attempt: .browserRetry(operationBrowserLease))
                    } else {
                        await play(item)
                    }
                }
            case .download:
                if let lease = operationBrowserLease {
                    startDownloadQueue(
                        saved,
                        attempt: .browserRetry(lease),
                        leaseToRevoke: lease
                    )
                    operationBrowserLease = nil
                } else {
                    startDownloadQueue(saved)
                }
            }

            try Task.checkCancellation()
            selectedFolderID = archive.destinationFolderID
            await refreshItems()
            if archive.itemResults.contains(where: {
                if case .moved = $0 { return true }
                return false
            }) {
                activityMessage = "已将现有音频移到“\(selectedFolderTitle() ?? "目标文件夹")”；播放进度和离线文件已保留。"
                launchOwnedTask { [weak self] in
                    try? await Task.sleep(for: .seconds(3))
                    guard self?.activityMessage?.hasPrefix("已将现有音频") == true else { return }
                    self?.activityMessage = nil
                }
            }
            return saved
        } catch {
            guard !isCancellation(error) else { return nil }
            present(error)
            return nil
        }
    }

    func play(
        _ requestedItem: AudioItem,
        attempt: ImportAttempt = .anonymous,
        isExpiryRecovery: Bool = false,
        consumesQueueEntry: Bool = false
    ) async {
        Self.playbackPerformanceSignposter.emitEvent("play.request")
        if !isExpiryRecovery {
            playbackRecoveryAttempts.remove(requestedItem.id)
        }
        playbackRequestGeneration &+= 1
        let requestGeneration = playbackRequestGeneration
        pendingQueueConsumptionItemID = nil
        do {
            try Task.checkCancellation()
            let database = try requireDatabase()
            var item = try await database.item(id: requestedItem.id) ?? requestedItem
            guard playbackRequestGeneration == requestGeneration else { return }
            presentPreparingPlayback(item)

            let playbackURL: URL
            let headers: [String: String]
            let mimeType: String?

            if item.storageKind == .offline {
                if item.downloadState == .available,
                    let relativePath = item.localMediaRelativePath,
                    let mediaStore,
                    await mediaStore.containsFile(at: relativePath)
                {
                    playbackURL = try mediaStore.absoluteURL(for: relativePath)
                    headers = [:]
                    mimeType = nil
                } else {
                    if item.downloadState == .available {
                        item = try await database.updateDownloadState(
                            for: item.id,
                            state: .failed
                        )
                        guard playbackRequestGeneration == requestGeneration else { return }
                        applyItemChange(item)
                    }
                    activityMessage = "本地音频不可用，正在准备在线播放…"
                    let stream = try await resolveOnlineStream(for: item, attempt: attempt)
                    try Task.checkCancellation()
                    guard playbackRequestGeneration == requestGeneration else { return }
                    activityMessage = nil
                    playbackURL = stream.url
                    headers = stream.headers
                    mimeType = stream.mimeType
                }
            } else {
                activityMessage = "正在准备播放…"
                let stream = try await resolveOnlineStream(for: item, attempt: attempt)
                try Task.checkCancellation()
                guard playbackRequestGeneration == requestGeneration else { return }
                activityMessage = nil
                playbackURL = stream.url
                headers = stream.headers
                mimeType = stream.mimeType
            }

            try Task.checkCancellation()
            if !consumesQueueEntry {
                try await database.setCurrentPlaybackItem(item.id)
            }
            guard playbackRequestGeneration == requestGeneration else { return }
            pendingQueueConsumptionItemID = consumesQueueEntry ? item.id : nil
            resolvingPlaybackItem = nil
            playbackController.load(
                item: item,
                url: playbackURL,
                headers: headers,
                mimeType: mimeType,
                resumeAt: item.playbackPosition,
                autoplay: true
            )
            if !consumesQueueEntry {
                replaceCurrentItemIfNeeded(item)
            }
            synchronizePlaybackPresentation()
        } catch {
            guard playbackRequestGeneration == requestGeneration else { return }
            resolvingPlaybackItem = nil
            synchronizePlaybackPresentation()
            activityMessage = nil
            guard !isCancellation(error) else { return }
            if consumesQueueEntry {
                playbackQueue.retainFailedHead(
                    message: normalizedImportError(error).localizedDescription)
            }
            if let request = (error as? ContentImportError).flatMap(verificationRequest(from:)) {
                requireVerification(
                    request,
                    toRetry: consumesQueueEntry
                        ? .queuedPlayback(requestedItem) : .play(requestedItem)
                )
                return
            }
            present(normalizedImportError(error))
        }
    }

    func playNow(_ item: AudioItem) {
        let isQueued = playbackQueue.session.entries.contains { $0.item.id == item.id }
        launchOwnedTask { [weak self] in
            await self?.play(item, consumesQueueEntry: isQueued)
        }
    }

    private func resolveOnlineStream(
        for item: AudioItem,
        attempt: ImportAttempt
    ) async throws -> ResolvedAudioStream {
        if let cached = await resolvedStreamCache.stream(for: item) {
            return cached
        }

        let interval = Self.playbackPerformanceSignposter.beginInterval("stream.resolve")
        defer { Self.playbackPerformanceSignposter.endInterval("stream.resolve", interval) }
        let stream = try await importer.resolveStream(
            for: metadata(from: item),
            attempt: attempt
        )
        await resolvedStreamCache.insert(stream, for: item)
        return stream
    }

    private func presentPreparingPlayback(_ item: AudioItem) {
        resolvingPlaybackItem = item
        playbackPresentation.update(
            PlaybackSnapshot(
                item: item,
                phase: .loading,
                currentTime: item.playbackPosition,
                duration: item.duration ?? 0,
                listeningHistory: item.listeningHistory,
                rate: preferences.playbackRate,
                artworkURL: absoluteArtworkURL(for: item)
            ),
            outputVolume: playbackController.volume,
            outputRevision: playbackController.outputRevision
        )
    }

    func playQueuedItem(_ itemID: UUID) {
        guard let entry = playbackQueue.session.entries.first(where: { $0.item.id == itemID })
        else {
            return
        }
        playNow(entry.item)
    }

    func enqueueNext(_ item: AudioItem) {
        enqueue(item, at: .next, feedback: "已加入下一项播放。")
    }

    func enqueueLast(_ item: AudioItem) {
        enqueue(item, at: .last, feedback: "已加入播放队尾。")
    }

    func removeQueueItem(_ itemID: UUID) {
        launchOwnedTask { [weak self] in
            guard let self else { return }
            do {
                try await playbackQueue.remove(itemID)
            } catch {
                playbackQueue.retainFailedHead(message: error.localizedDescription)
            }
        }
    }

    func moveQueueItem(_ itemID: UUID, to position: Int) {
        launchOwnedTask { [weak self] in
            guard let self else { return }
            do {
                try await playbackQueue.move(itemID, to: position)
            } catch {
                present(error)
            }
        }
    }

    func clearPlaybackQueue() {
        launchOwnedTask { [weak self] in
            guard let self else { return }
            do {
                try await playbackQueue.clear()
            } catch {
                playbackQueue.retainFailedHead(message: error.localizedDescription)
            }
        }
    }

    func retryQueuePlayback() {
        guard let nextItem = playbackQueue.session.nextItem else { return }
        launchOwnedTask { [weak self] in
            await self?.play(nextItem, consumesQueueEntry: true)
        }
    }

    private func enqueue(
        _ item: AudioItem,
        at placement: PlaybackQueuePlacement,
        feedback: String
    ) {
        guard item.id != currentItem?.id else {
            let currentItemFeedback = "该音频已是当前播放项。"
            activityMessage = currentItemFeedback
            launchOwnedTask { [weak self] in
                try? await Task.sleep(for: .seconds(2))
                guard self?.activityMessage == currentItemFeedback else { return }
                self?.activityMessage = nil
            }
            return
        }
        launchOwnedTask { [weak self] in
            guard let self else { return }
            do {
                try await playbackQueue.enqueue(item.id, at: placement)
                activityMessage = feedback
                try? await Task.sleep(for: .seconds(2))
                guard activityMessage == feedback else { return }
                activityMessage = nil
            } catch {
                present(error)
            }
        }
    }

    private func consumeReadyQueueItemIfNeeded(_ itemID: UUID) async {
        guard pendingQueueConsumptionItemID == itemID else { return }
        do {
            let activatedItem = try await playbackQueue.activateAfterPlaybackIsReady(itemID)
            guard pendingQueueConsumptionItemID == itemID else { return }
            pendingQueueConsumptionItemID = nil
            replaceCurrentItemIfNeeded(activatedItem)
            synchronizePlaybackPresentation()
        } catch {
            playbackQueue.retainFailedHead(message: "播放已切换，但队列状态未能更新。")
            await AppDiagnostics.shared.record(
                level: .warning,
                category: "playback",
                event: "queue.consume-after-ready.failed",
                error: PresentedError.from(error)
            )
        }
    }

    private func advancePlaybackQueue(after itemID: UUID) async {
        guard currentItem?.id == itemID,
            playbackController.state == .finished,
            let nextItem = playbackQueue.session.nextItem
        else {
            return
        }
        await play(nextItem, consumesQueueEntry: true)
    }

    private func handlePlaybackFailure(itemID: UUID, message: String, statusCode: Int?) async {
        await resolvedStreamCache.invalidate(itemID: itemID)
        let wasQueuedPlayback = pendingQueueConsumptionItemID == itemID
        if wasQueuedPlayback {
            playbackQueue.retainFailedHead(message: message)
        }
        await recoverExpiredPlaybackIfPossible(
            itemID: itemID,
            message: message,
            statusCode: statusCode,
            consumesQueueEntry: wasQueuedPlayback
        )
    }

    private func recoverExpiredPlaybackIfPossible(
        itemID: UUID,
        message: String,
        statusCode: Int?,
        consumesQueueEntry: Bool = false
    ) async {
        let storedItem: AudioItem?
        if let database {
            do {
                storedItem = try await database.item(id: itemID)
            } catch {
                await AppDiagnostics.shared.record(
                    level: .warning, category: "playback", event: "recovery.lookup.failed",
                    error: PresentedError.from(error))
                storedItem = nil
            }
        } else {
            storedItem = nil
        }
        guard let statusCode, [401, 403, 410].contains(statusCode),
            !playbackRecoveryAttempts.contains(itemID),
            let database,
            var refreshedItem = storedItem,
            refreshedItem.storageKind == .online
        else {
            present(ContentImportError.mediaUnavailable(message))
            return
        }
        playbackRecoveryAttempts.insert(itemID)
        refreshedItem.playbackPosition = playbackController.currentTime
        do {
            _ = try await database.updatePlaybackPosition(
                for: itemID, position: refreshedItem.playbackPosition)
        } catch {
            await AppDiagnostics.shared.record(
                level: .warning, category: "playback", event: "recovery.position.persist.failed",
                error: PresentedError.from(error))
        }
        await play(
            refreshedItem,
            isExpiryRecovery: true,
            consumesQueueEntry: consumesQueueEntry
        )
    }

    func togglePlayback() {
        guard let currentItem else { return }
        if playbackController.currentItem?.id == currentItem.id {
            playbackController.togglePlayback()
        } else {
            launchOwnedTask { [weak self] in
                await self?.play(currentItem)
            }
        }
    }

    func retryPlayback() {
        guard let item = playbackController.currentItem ?? currentItem else { return }
        let consumesQueueEntry = playbackQueue.session.entries.contains { $0.item.id == item.id }
        launchOwnedTask { [weak self] in
            await self?.play(item, consumesQueueEntry: consumesQueueEntry)
        }
    }

    func resumePlayback() {
        guard let currentItem else { return }
        if playbackController.currentItem?.id == currentItem.id {
            playbackController.play()
        } else {
            launchOwnedTask { [weak self] in
                await self?.play(currentItem)
            }
        }
    }

    func pausePlayback() {
        playbackController.pause()
    }

    func skipBackward() {
        playbackController.skipBackward()
    }

    func skipForward() {
        playbackController.skipForward()
    }

    func seek(to time: TimeInterval) {
        playbackController.seek(to: time)
    }

    func setPlaybackRate(_ rate: Double) {
        guard AppPreferences.supportedPlaybackRates.contains(rate) else { return }
        preferences.playbackRate = rate
        playbackController.setRate(rate)
    }

    var playbackOutputController: AudioPlaybackController { playbackController }

    func setPlaybackVolume(_ volume: Double) {
        playbackController.setVolume(volume)
    }

    func commitPlaybackVolume() {
        preferences.playbackVolume = playbackController.volume
    }

    func startDownload(
        _ requestedItem: AudioItem,
        attempt: ImportAttempt = .anonymous,
        leaseToRevoke: BrowserAccessLease? = nil
    ) {
        guard reserveDownload(for: requestedItem.id) else { return }
        let task = Task { [weak self] in
            guard let self else { return }
            await self.performReservedDownload(
                requestedItem,
                attempt: attempt,
                leaseToRevoke: leaseToRevoke
            )
        }
        activeDownloadTask = task
    }

    private func startDownloadQueue(
        _ requestedItems: [AudioItem],
        attempt: ImportAttempt = .anonymous,
        leaseToRevoke: BrowserAccessLease? = nil
    ) {
        guard let first = requestedItems.first, reserveDownload(for: first.id) else { return }
        activeDownloadTask = Task { [weak self] in
            guard let self else { return }
            await self.performDownloadQueue(
                requestedItems,
                attempt: attempt,
                leaseToRevoke: leaseToRevoke
            )
        }
    }

    func cancelDownload(for itemID: UUID? = nil) {
        guard let activeDownloadItemID,
            itemID == nil || itemID == activeDownloadItemID
        else { return }
        activeDownloadTask?.cancel()
    }

    private func performReservedDownload(
        _ requestedItem: AudioItem,
        attempt: ImportAttempt,
        leaseToRevoke: BrowserAccessLease?
    ) async {
        defer {
            finishDownloadReservation(for: requestedItem.id)
            leaseToRevoke?.revoke()
        }
        guard activeDownloadItemID == requestedItem.id else {
            return
        }
        do {
            try await performDownload(requestedItem, attempt: attempt)
        } catch {
            if let request = (error as? ContentImportError).flatMap(verificationRequest(from:)) {
                requireVerification(request, toRetry: .download(requestedItem))
            } else {
                present(normalizedImportError(error))
            }
        }
    }

    private func performDownloadQueue(
        _ requestedItems: [AudioItem],
        attempt: ImportAttempt,
        leaseToRevoke: BrowserAccessLease?
    ) async {
        var failedCount = 0
        defer {
            finishDownloadQueue()
            leaseToRevoke?.revoke()
            if failedCount > 0 {
                userFacingError = .message(
                    "有 \(failedCount) 条音频下载失败；其他条目已继续处理，可稍后重新选择失败项。", code: .fileSystem)
            }
        }
        for item in requestedItems {
            do {
                try Task.checkCancellation()
                activeDownloadItemID = item.id
                activeDownloadProgress = .indeterminate
                activityMessage = "正在下载 \(item.title)…"
                try await performDownload(item, attempt: attempt)
            } catch {
                if isCancellation(error) { return }
                failedCount += 1
            }
        }
    }

    private func performDownload(
        _ requestedItem: AudioItem,
        attempt: ImportAttempt
    ) async throws {
        let database = try requireDatabase()
        let mediaStore = try requireMediaStore()
        var item = try await database.item(id: requestedItem.id) ?? requestedItem
        guard activeDownloadItemID == item.id else { return }

        if item.downloadState == .available,
            let localMediaRelativePath = item.localMediaRelativePath,
            await mediaStore.containsFile(at: localMediaRelativePath)
        {
            return
        }

        if item.downloadState == .available {
            do { try await mediaStore.removeDownloadedAudio(for: item.id) } catch {
                await AppDiagnostics.shared.record(
                    level: .warning, category: "storage",
                    event: "download.stale-media.cleanup.failed", error: PresentedError.from(error))
            }
            let failed = try await database.updateDownloadState(for: item.id, state: .failed)
            applyItemChange(failed)
            item = failed
        }

        var markedDownloading = false
        do {
            let downloading = try await database.updateDownloadState(
                for: item.id, state: .downloading)
            markedDownloading = true
            item = downloading
            applyItemChange(downloading)
            try Task.checkCancellation()

            let destination = try await mediaStore.resetMediaDirectory(for: item.id)
            let downloadingItemID = item.id
            let downloaded = try await importer.download(
                content: metadata(from: item),
                to: destination,
                attempt: attempt
            ) { [weak self] progress in
                Task { @MainActor [weak self] in
                    guard self?.activeDownloadItemID == downloadingItemID else { return }
                    self?.activeDownloadProgress = progress
                }
            }
            try Task.checkCancellation()
            let relativePath = mediaStore.relativeAudioPath(for: item.id)
            let expectedURL = try mediaStore.absoluteURL(for: relativePath)
            guard downloaded.url == expectedURL else {
                throw ContentImportError.invalidDownloadedAudio
            }
            let available = try await database.completeDownload(
                for: item.id,
                localMediaRelativePath: relativePath,
                duration: downloaded.duration
            )
            applyItemChange(available)
        } catch {
            if markedDownloading {
                do { try await mediaStore.removeDownloadedAudio(for: item.id) } catch {
                    await AppDiagnostics.shared.record(
                        level: .warning, category: "storage",
                        event: "download.failed-media.cleanup.failed",
                        error: PresentedError.from(error))
                }
                let state: AudioDownloadState = isCancellation(error) ? .notRequested : .failed
                do {
                    let updated = try await database.updateDownloadState(for: item.id, state: state)
                    applyItemChange(updated)
                } catch {
                    await AppDiagnostics.shared.record(
                        level: .warning, category: "database",
                        event: "download.failure-state.persist.failed",
                        error: PresentedError.from(error))
                }
            }
            throw error
        }
    }

    func moveItem(_ id: UUID, to folderID: UUID) async {
        do {
            let database = try requireDatabase()
            let moved = try await database.moveItem(id, toFolderID: folderID)
            applyItemChange(moved)
        } catch {
            present(error)
        }
    }

    func deleteItem(_ id: UUID) async {
        guard activeDownloadItemID != id else {
            userFacingError = .message("正在下载这条音频，请先取消下载。")
            return
        }
        artworkTasks.removeValue(forKey: id)?.cancel()
        artworkTaskTokens.removeValue(forKey: id)
        do {
            let database = try requireDatabase()
            guard let item = try await database.item(id: id) else {
                throw MarketDatabaseError.itemNotFound(id)
            }
            if currentItem?.id == id {
                playbackController.stop()
                replaceCurrentItemIfNeeded(nil)
            }
            try await database.deleteItem(id)
            try? await playbackQueue.reload()
            if let mediaStore {
                do { try await mediaStore.removeMedia(for: item.id) } catch {
                    await AppDiagnostics.shared.record(
                        level: .warning, category: "storage",
                        event: "item.delete-media.cleanup.failed", error: PresentedError.from(error)
                    )
                }
            }
            removeItemFromCurrentPage(id)
            synchronizePlaybackPresentation()
        } catch {
            present(error)
        }
    }

    func flushPlaybackPosition() async {
        playbackController.flushPlaybackPosition()
        guard let database, let item = playbackController.currentItem else { return }
        do {
            _ = try await database.updatePlaybackPosition(
                for: item.id,
                position: playbackController.currentTime
            )
        } catch {
            present(error)
        }
    }

    private func refreshFolders() async {
        do {
            let database = try requireDatabase()
            let refreshedFolders = try await database.allFolders()
            cachedFolderTree = makeFolderTree(from: refreshedFolders)
            folders = refreshedFolders
        } catch {
            present(error)
        }
    }

    private struct ItemRefreshRequest: Sendable {
        let collection: LibraryCollection
        let generation: UInt
    }

    private func itemRefreshRequest() -> ItemRefreshRequest {
        ItemRefreshRequest(collection: selectedCollection, generation: itemRefreshGeneration)
    }

    private func refreshItems() async {
        itemRefreshGeneration &+= 1
        let request = itemRefreshRequest()
        beginLoadingItems(for: request.collection)
        itemRefreshTask?.cancel()
        itemRefreshTask = nil
        await refreshItems(for: request)
    }

    private func refreshItems(for request: ItemRefreshRequest) async {
        #if DEBUG || PODPIN_TESTING
            defer { itemRefreshCompletionTestHook?(request.collection) }
        #endif
        do {
            try await refreshItemsOrThrow(for: request)
        } catch {
            if isCurrentItemRefreshRequest(request) {
                cachedVisibleItems = []
                items = []
                let presented = PresentedError.from(error)
                itemsPhase = .failed(request.collection, presented)
                await AppDiagnostics.shared.record(
                    level: .error, category: "library", event: "refresh.failed", error: presented)
            }
        }
    }

    private func refreshItemsOrThrow(for request: ItemRefreshRequest) async throws {
        let database = try requireDatabase()
        let interval = Self.performanceSignposter.beginInterval("folder.first-page")
        defer { Self.performanceSignposter.endInterval("folder.first-page", interval) }
        let page = try await database.listItemPage(in: request.collection)
        #if DEBUG || PODPIN_TESTING
            if let itemRefreshTestHook {
                await itemRefreshTestHook(request.collection)
            }
        #endif
        guard !Task.isCancelled, isCurrentItemRefreshRequest(request) else { return }
        cachedVisibleItems = makeVisibleItems(from: page.items)
        items = page.items
        nextItemCursor = page.nextCursor
        canLoadMoreItems = page.nextCursor != nil
        itemsPhase = page.items.isEmpty ? .empty(request.collection) : .loaded(request.collection)
    }

    private func beginLoadingItems(for collection: LibraryCollection) {
        cachedVisibleItems = []
        items = []
        nextItemCursor = nil
        canLoadMoreItems = false
        itemsPhase = .loading(collection)
    }

    private func isCurrentItemRefreshRequest(_ request: ItemRefreshRequest) -> Bool {
        selectedCollection == request.collection && itemRefreshGeneration == request.generation
    }

    func loadMoreItems() {
        guard !isLoadingMoreItems,
            let cursor = nextItemCursor,
            itemsPhase == .loaded(selectedCollection)
        else { return }
        isLoadingMoreItems = true
        let collection = selectedCollection
        let generation = itemRefreshGeneration
        itemLoadMoreTask = Task { [weak self] in
            guard let self else { return }
            defer {
                self.isLoadingMoreItems = false
                self.itemLoadMoreTask = nil
            }
            do {
                let database = try self.requireDatabase()
                let page = try await database.listItemPage(in: collection, after: cursor)
                guard self.selectedCollection == collection,
                    self.itemRefreshGeneration == generation,
                    !Task.isCancelled
                else { return }
                self.appendPage(page)
            } catch {
                guard !Task.isCancelled else { return }
                self.present(error, category: "library", event: "page.load-more.failed")
            }
        }
    }

    private func appendPage(_ page: ItemPage) {
        let existingIDs = Set(items.map(\.id))
        let additions = page.items.filter { !existingIDs.contains($0.id) }
        items.append(contentsOf: additions)
        cachedVisibleItems.append(contentsOf: makeVisibleItems(from: additions))
        nextItemCursor = page.nextCursor
        canLoadMoreItems = page.nextCursor != nil
    }

    private func applyItemChange(_ item: AudioItem) {
        refreshPlaybackItemIfNeeded(item)

        guard collectionContains(item, in: selectedCollection) else {
            removeItemFromCurrentPage(item.id)
            return
        }
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index] = item
            cachedVisibleItems[index] = makeVisibleItem(from: item)
            return
        }
        guard !canLoadMoreItems || items.count < 200 else { return }
        let insertionIndex =
            items.firstIndex(where: { !isOrderedBefore($0, item) }) ?? items.endIndex
        items.insert(item, at: insertionIndex)
        cachedVisibleItems.insert(makeVisibleItem(from: item), at: insertionIndex)
    }

    private func refreshPlaybackItemIfNeeded(_ item: AudioItem) {
        let isCurrentItem = currentItem?.id == item.id
        let isLoadedItem = playbackController.currentItem?.id == item.id
        let isResolvingItem = resolvingPlaybackItem?.id == item.id
        guard isCurrentItem || isLoadedItem || isResolvingItem else { return }

        if isCurrentItem || isLoadedItem {
            replaceCurrentItemIfNeeded(item)
        }
        if isResolvingItem {
            resolvingPlaybackItem = item
        }
        synchronizePlaybackPresentation()
    }

    private func removeItemFromCurrentPage(_ itemID: UUID) {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else { return }
        items.remove(at: index)
        cachedVisibleItems.remove(at: index)
        if items.isEmpty, itemsPhase == .loaded(selectedCollection) {
            itemsPhase = .empty(selectedCollection)
        }
    }

    private func makeVisibleItem(from item: AudioItem) -> LibraryItemRow {
        LibraryItemRow(
            id: item.id,
            folderID: item.folderID,
            title: item.title,
            author: item.author,
            sourceName: sourceName(for: item.platform),
            duration: item.duration,
            importedAt: item.importedAt,
            storageState: libraryStorageState(for: item),
            progress: item.playbackPosition,
            listeningHistory: item.listeningHistory,
            artworkURL: absoluteArtworkURL(for: item)
        )
    }

    private func isOrderedBefore(_ lhs: AudioItem, _ rhs: AudioItem) -> Bool {
        let lhsSortDate: Date
        let rhsSortDate: Date
        if selectedCollection == .recentlyPlayed {
            lhsSortDate = lhs.lastPlayedAt ?? .distantPast
            rhsSortDate = rhs.lastPlayedAt ?? .distantPast
        } else {
            lhsSortDate = lhs.importedAt
            rhsSortDate = rhs.importedAt
        }
        if lhsSortDate != rhsSortDate { return lhsSortDate > rhsSortDate }
        return lhs.id.uuidString.localizedCaseInsensitiveCompare(rhs.id.uuidString)
            == .orderedDescending
    }

    private func collectionContains(_ item: AudioItem, in collection: LibraryCollection) -> Bool {
        switch collection {
        case .recentlyImported:
            true
        case .recentlyPlayed:
            item.lastPlayedAt != nil
        case .downloaded:
            item.downloadState == .available
        case .folder(let folderID):
            item.folderID == folderID
        }
    }

    private func startArtworkCaching(from artworkURL: URL, for itemID: UUID) {
        artworkTasks.removeValue(forKey: itemID)?.cancel()
        let token = UUID()
        artworkTaskTokens[itemID] = token
        let task = Task<Void, Never> { [weak self] in
            guard let self else { return }
            await self.cacheArtwork(from: artworkURL, for: itemID, token: token)
        }
        artworkTasks[itemID] = task
    }

    private func cacheArtwork(
        from artworkURL: URL,
        for itemID: UUID,
        token: UUID
    ) async {
        defer {
            if artworkTaskTokens[itemID] == token {
                artworkTasks.removeValue(forKey: itemID)
                artworkTaskTokens.removeValue(forKey: itemID)
            }
        }
        guard let database, let mediaStore else { return }
        let temporaryURL = mediaStore.temporaryArtworkURL(for: itemID)
        do {
            let relativePath = mediaStore.relativeArtworkPath(for: itemID)
            try await artworkDownloader.cacheArtwork(from: artworkURL, to: temporaryURL)
            try Task.checkCancellation()
            if artworkTaskTokens[itemID] == token,
                try await database.item(id: itemID) != nil
            {
                try await mediaStore.installArtwork(at: temporaryURL, for: itemID)
                let updatedItem = try await database.updateArtworkPath(
                    for: itemID,
                    relativePath: relativePath
                )
                if currentItem?.id == itemID {
                    replaceCurrentItemIfNeeded(updatedItem)
                    synchronizePlaybackPresentation()
                }
                applyItemChange(updatedItem)
            }
        } catch {
            // Artwork is auxiliary source metadata. The audio item remains useful
            // without it, so failure intentionally stays non-blocking.
        }
        await mediaStore.removeTemporaryArtwork(at: temporaryURL)
    }

    private func persistPlaybackPosition(
        id: UUID,
        position: TimeInterval,
        listeningHistory: ListeningHistory,
        force: Bool
    ) {
        guard let database else { return }
        if force { needsNowPlayingTimeSync = true }
        applyPlaybackUpdate(
            id: id,
            position: position,
            listeningHistory: listeningHistory
        )
        launchOwnedTask { [weak self] in
            do {
                _ = try await database.updatePlaybackPosition(
                    for: id,
                    position: position,
                    listeningHistory: listeningHistory
                )
            } catch {
                if force { self?.present(error) }
            }
        }
    }

    private func applyPlaybackUpdate(
        id: UUID,
        position: TimeInterval,
        listeningHistory: ListeningHistory
    ) {
        let normalizedPosition = position.isFinite ? max(position, 0) : 0
        if let index = items.firstIndex(where: { $0.id == id }) {
            var updated = items[index]
            updated.playbackPosition = min(
                normalizedPosition, updated.duration ?? normalizedPosition)
            updated.listeningHistory = listeningHistory
            updated.lastPlayedAt = .now
            items[index] = updated
            cachedVisibleItems[index] = makeVisibleItem(from: updated)
            return
        }
        guard var updated = currentItem, updated.id == id else { return }
        updated.playbackPosition = min(normalizedPosition, updated.duration ?? normalizedPosition)
        updated.listeningHistory = listeningHistory
        updated.lastPlayedAt = .now
        guard collectionContains(updated, in: selectedCollection),
            !canLoadMoreItems || items.count < 200
        else { return }
        let insertionIndex =
            items.firstIndex(where: { !isOrderedBefore($0, updated) }) ?? items.endIndex
        items.insert(updated, at: insertionIndex)
        cachedVisibleItems.insert(makeVisibleItem(from: updated), at: insertionIndex)
    }

    private func synchronizePlaybackPresentation() {
        if let resolvingItem = resolvingPlaybackItem {
            let preparingSnapshot = PlaybackSnapshot(
                item: resolvingItem,
                phase: .loading,
                currentTime: resolvingItem.playbackPosition,
                duration: resolvingItem.duration ?? 0,
                listeningHistory: resolvingItem.listeningHistory,
                rate: preferences.playbackRate,
                artworkURL: absoluteArtworkURL(for: resolvingItem)
            )
            playbackPresentation.update(
                preparingSnapshot,
                outputVolume: playbackController.volume,
                outputRevision: playbackController.outputRevision
            )
            if currentPlaybackPhase != .loading {
                currentPlaybackPhase = .loading
            }
            return
        }

        let controllerItem = playbackController.currentItem
        let loadedItem: AudioItem?
        if let currentItem, controllerItem?.id == currentItem.id {
            // Database-backed metadata such as artwork and download state can
            // change while the same AVPlayer item remains loaded.
            loadedItem = currentItem
        } else {
            loadedItem = controllerItem ?? currentItem
        }
        replaceCurrentItemIfNeeded(loadedItem)

        let duration =
            playbackController.duration > 0
            ? playbackController.duration
            : (loadedItem?.duration ?? 0)
        let snapshot = PlaybackSnapshot(
            item: loadedItem,
            phase: playbackController.state,
            currentTime: playbackController.currentItem == nil
                ? (loadedItem?.playbackPosition ?? 0)
                : playbackController.currentTime,
            duration: duration,
            listeningHistory: playbackController.currentItem == nil
                ? (loadedItem?.listeningHistory ?? ListeningHistory())
                : playbackController.listeningHistory,
            rate: playbackController.rate,
            artworkURL: loadedItem.flatMap(absoluteArtworkURL(for:))
        )
        playbackPresentation.update(
            snapshot,
            outputVolume: playbackController.volume,
            outputRevision: playbackController.outputRevision
        )
        if currentPlaybackPhase != snapshot.phase {
            currentPlaybackPhase = snapshot.phase
        }

        let identity = NowPlayingIdentity(snapshot: snapshot)
        guard needsNowPlayingTimeSync || identity != lastNowPlayingIdentity else { return }
        nowPlayingController.publish(
            item: snapshot.item,
            time: snapshot.currentTime,
            duration: snapshot.duration,
            rate: snapshot.rate,
            isPlaying: snapshot.isPlaying,
            artworkURL: snapshot.item.flatMap(absoluteArtworkURL(for:))
        )
        lastNowPlayingIdentity = identity
        needsNowPlayingTimeSync = false
    }

    private func replaceCurrentItemIfNeeded(_ item: AudioItem?) {
        guard currentItem != item else { return }
        currentItem = item
        needsNowPlayingTimeSync = true
    }

    private struct NowPlayingIdentity: Equatable {
        let itemID: UUID?
        let title: String?
        let author: String?
        let artworkPath: String?
        let duration: TimeInterval
        let rate: Double
        let phase: PlaybackPhase

        init(snapshot: PlaybackSnapshot) {
            itemID = snapshot.item?.id
            title = snapshot.item?.title
            author = snapshot.item?.author
            artworkPath = snapshot.item?.artworkRelativePath
            duration = snapshot.duration
            rate = snapshot.rate
            phase = snapshot.phase
        }
    }

    private func metadata(from item: AudioItem) -> ImportedAudioMetadata {
        ImportedAudioMetadata(
            platform: item.platform,
            contentID: item.contentID,
            sourceURL: item.sourceURL,
            title: item.title,
            author: item.author,
            artworkURL: nil,
            duration: item.duration
        )
    }

    private func absoluteArtworkURL(for item: AudioItem) -> URL? {
        guard let relativePath = item.artworkRelativePath,
            let mediaStore
        else { return nil }
        return try? mediaStore.absoluteURL(for: relativePath)
    }

    func artworkURL(for item: AudioItem) -> URL? {
        absoluteArtworkURL(for: item)
    }

    private func libraryStorageState(for item: AudioItem) -> LibraryItemRow.StorageState {
        switch item.downloadState {
        case .downloading: .downloading
        case .available: .downloaded
        case .failed: .downloadFailed
        case .notRequested: .online
        }
    }

    private func reserveDownload(for itemID: UUID) -> Bool {
        guard activeDownloadItemID == nil else {
            userFacingError = .message("PodPin 一次只能下载一条音频。")
            return false
        }
        activeDownloadItemID = itemID
        activeDownloadProgress = .indeterminate
        activityMessage = "正在下载音频…"
        return true
    }

    private func finishDownloadReservation(for itemID: UUID) {
        guard activeDownloadItemID == itemID else { return }
        activeDownloadItemID = nil
        activeDownloadProgress = .indeterminate
        activeDownloadTask = nil
        activityMessage = nil
    }

    private func finishDownloadQueue() {
        activeDownloadItemID = nil
        activeDownloadProgress = .indeterminate
        activeDownloadTask = nil
        activityMessage = nil
    }

    private func normalizedImportError(_ error: Error) -> Error {
        if error is CancellationError { return ContentImportError.cancelled }
        return error
    }

    private func requireVerification(
        _ request: PlatformVerificationRequest,
        toRetry operation: VerificationOperation
    ) {
        verificationRequest = request
        verificationOperation = operation
        importIssue = nil
        browserProfiles = []
        hasRequestedBrowserProfiles = false
        isDiscoveringBrowserProfiles = false
        browserProfileTask?.cancel()
        browserProfileTask = nil
    }

    func discoverBrowserProfiles() {
        guard verificationRequest != nil, !isDiscoveringBrowserProfiles else { return }
        hasRequestedBrowserProfiles = true
        isDiscoveringBrowserProfiles = true
        browserProfileTask?.cancel()
        browserProfileTask = Task { [weak self] in
            guard let self else { return }
            let profiles = await browserAccessAuthorizer.profiles()
            guard !Task.isCancelled, verificationRequest != nil else { return }
            browserProfiles = profiles
            isDiscoveringBrowserProfiles = false
            browserProfileTask = nil
        }
    }

    private func verificationRequest(
        from error: ContentImportError
    ) -> PlatformVerificationRequest? {
        switch error {
        case .browserAccessRequired(let request):
            request
        default:
            nil
        }
    }

    private func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        return (error as? ContentImportError) == .cancelled
    }

    private func sourceName(for platform: AudioPlatform) -> String {
        switch platform {
        case .fixture: "PodPin"
        case .bilibili: "B 站"
        case .douyin: "抖音"
        case .fireside: "Fireside"
        case .xiaoyuzhou: "小宇宙"
        }
    }

    private func requireDatabase() throws -> MarketDatabase {
        guard !isShutDown, let database else { throw StoreError.notStarted }
        return database
    }

    private func requireMediaStore() throws -> PodPinMediaStore {
        guard !isShutDown, let mediaStore else { throw StoreError.notStarted }
        return mediaStore
    }

    /// Starts a short user-requested library mutation under the module session.
    /// The store cancels and drains the work during shutdown; the deadline keeps
    /// a stalled local database or filesystem operation from running forever.
    func performLibraryOperation(
        timeout: Duration = .seconds(10),
        _ operation: @escaping @MainActor @Sendable () async -> Void
    ) {
        launchOwnedTask(timeout: timeout, operation)
    }

    private func launchOwnedTask(
        timeout: Duration? = nil,
        _ operation: @escaping @MainActor @Sendable () async -> Void
    ) {
        guard !isShutDown else { return }
        let identifier = UUID()
        let task = Task { @MainActor [weak self] in
            await Task.yield()
            guard !Task.isCancelled else {
                self?.finishOwnedTask(identifier)
                return
            }
            await operation()
            self?.finishOwnedTask(identifier)
        }
        ownedTasks[identifier] = task
        if let timeout {
            ownedTaskTimeouts[identifier] = Task { @MainActor [weak self] in
                do {
                    try await Task.sleep(for: timeout)
                } catch {
                    return
                }
                self?.ownedTasks[identifier]?.cancel()
            }
        }
    }

    private func finishOwnedTask(_ identifier: UUID) {
        ownedTaskTimeouts.removeValue(forKey: identifier)?.cancel()
        ownedTasks[identifier] = nil
    }

    private func present(
        _ error: Error, category: String = "app", event: String = "operation.failed"
    ) {
        guard !isShutDown, !isCancellation(error) else { return }
        let presented = PresentedError.from(error)
        userFacingError = presented
        launchOwnedTask {
            await AppDiagnostics.shared.record(
                level: .error, category: category, event: event, error: presented)
        }
    }
}

private enum StoreError: LocalizedError {
    case notStarted

    var errorDescription: String? {
        switch self {
        case .notStarted: "PodPin 仍在打开本地资料库，请稍后重试。"
        }
    }
}
