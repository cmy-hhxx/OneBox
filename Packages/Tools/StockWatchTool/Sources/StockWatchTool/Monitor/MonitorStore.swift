import Combine
import Foundation
import OSLog
import Observation

#if DEBUG || STOCKWATCH_BENCHMARK
    enum AlertSettingsPersistenceEvent: Sendable, Equatable {
        case committed(AlertSettingsSnapshot, Int)
        case finished(AlertSettingsSnapshot, Int)
        case flushReturnedWithoutDraining(AlertSettingsSnapshot, Int)
        case flushAwaitingLineage(AlertSettingsSnapshot, Int)
    }
#endif

enum MonitorStoreOperation: Sendable, Equatable {
    case start
    case search
    case add
    case remove
    case move
    case importJSON
    case refresh
    case generateTargets
    case clearQuoteHistory
    case refreshQuoteBarCount
    case flushPersistence
}

enum MonitorStoreOperationError: LocalizedError, Sendable, Equatable {
    case unavailable

    var errorDescription: String? {
        tr("股票看盘已停止，操作未执行")
    }
}

@MainActor
final class MonitorStore: ObservableObject {
    private static let signposter = OSSignposter(
        subsystem: "com.cmy.OneBox.StockWatch",
        category: "MonitorStore"
    )

    @Published private var watchlist = Watchlist()
    @Published private var monitoredInstruments: [InstrumentID: MonitoredInstrument] = [:]
    @Published private(set) var lastRefresh: Date?
    @Published private(set) var sourceError: String?
    @Published private(set) var storageError: String?
    @Published private(set) var quoteBarCount = 0
    @Published private(set) var isWatchlistMutating = false
    @Published private(set) var activeAlert: AlertEvent?
    @Published private(set) var alertConfiguration = AlertConfiguration.default
    @Published private(set) var priceAlertTargets: [InstrumentID: PriceAlertTargets] = [:]

    var instruments: [Instrument] { watchlist.instruments }
    var databasePath: String { database.databasePath }

    private let client: any MarketDataClient
    private let database: MarketDatabase
    private let preferences: StockWatchPreferences
    private let refreshCoordinator: QuoteRefreshCoordinator
    private let alertDismissalDelay: Duration
    private let alertDismissalNow: @MainActor @Sendable () -> ContinuousClock.Instant
    private let alertDismissalSleep: @MainActor @Sendable (Duration) async throws -> Void
    private let alertSoundPlayer: any AlertSoundPlaying
    private let databaseClose: @Sendable (MarketDatabase) async throws -> Void
    private var initialRefreshTask: Task<Void, Never>?
    private var initialRefreshGeneration = 0
    private var refreshLoopTask: Task<Void, Never>?
    private var refreshLoopGeneration = 0
    private var refreshCycleTask: Task<Void, Never>?
    private var refreshCycleRevision: Int?
    private var refreshCycleGeneration = 0
    private var isClearingQuoteHistory = false
    private var pendingAlerts: [AlertEvent] = []
    private var dismissAlertTask: Task<Void, Never>?
    private var isAlertDismissalPaused = false
    private var alertDismissalRemaining: Duration?
    private var alertDismissalStartedAt: ContinuousClock.Instant?
    private var alertSettingsPersistenceTask: Task<String?, Never>?
    private var watchlistMutationTail: Task<Void, Never>?
    private var hasStarted = false
    private var hasStopped = false
    private var isShuttingDown = false
    private var hasClosedDatabase = false
    private var shutdownTask: Task<StockWatchShutdownFailure?, Never>?
    private var acceptsOperations = true
    private var admittedOperationCount = 0
    private var admittedOperationDrainWaiters: [CheckedContinuation<Void, Never>] = []
    private var watchlistRevision = 0
    private var pendingWatchlistMutations = 0
    private var alertSettingsRevision = 0
    private var lastPersistedAlertSettings = AlertSettingsSnapshot.default
    private var lastPersistedAlertSettingsRevision = 0
    #if DEBUG || STOCKWATCH_BENCHMARK
        var alertSettingsPersistenceEventObserverForTesting:
            (
                @MainActor @Sendable (AlertSettingsPersistenceEvent) async -> Void
            )?
        var operationAdmissionObserverForTesting:
            (@MainActor @Sendable (MonitorStoreOperation) async -> Void)?
        var acceptsOperationsForTesting: Bool { acceptsOperations }
        var isClearingQuoteHistoryForTesting: Bool { isClearingQuoteHistory }
        var pendingAlertCountForTesting: Int { pendingAlerts.count }
    #endif
    private var storageErrors: [StorageErrorContext: StorageErrorEntry] = [:]
    private var storageErrorRevision = 0
    private var alertEvaluators: [InstrumentID: AlertEvaluator] = [:]

    init(
        client: any MarketDataClient = PublicMarketDataClient(),
        database: MarketDatabase,
        preferences: StockWatchPreferences,
        alertSoundPlayer: any AlertSoundPlaying = NoOpAlertSoundPlayer(),
        maximumConcurrentRefreshes: Int = 6,
        alertDismissalDelay: Duration = .seconds(6),
        alertDismissalNow: @escaping @MainActor @Sendable () -> ContinuousClock.Instant = {
            ContinuousClock().now
        },
        alertDismissalSleep: @escaping @MainActor @Sendable (Duration) async throws -> Void = {
            try await Task.sleep(for: $0)
        },
        refreshNow: @escaping @Sendable (Market) -> Date = { _ in Date() },
        databaseClose: @escaping @Sendable (MarketDatabase) async throws -> Void = {
            try $0.close()
        }
    ) {
        self.client = client
        self.database = database
        self.preferences = preferences
        self.alertSoundPlayer = alertSoundPlayer
        self.refreshCoordinator = QuoteRefreshCoordinator(
            client: client,
            database: database,
            maximumConcurrentRequests: maximumConcurrentRefreshes,
            now: refreshNow
        )
        self.alertDismissalDelay = alertDismissalDelay
        self.alertDismissalNow = alertDismissalNow
        self.alertDismissalSleep = alertDismissalSleep
        self.databaseClose = databaseClose
        observeRefreshInterval()
    }

    private func observeRefreshInterval() {
        withObservationTracking {
            _ = preferences.refreshInterval
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.observeRefreshInterval()
                self.restartRefreshLoop()
            }
        }
    }

    func start() async throws {
        try await withAdmittedThrowingOperation(.start, requiresStarted: false) {
            try await startAdmitted()
        }
    }

    private func startAdmitted() async throws {
        guard !hasStarted else { return }
        try Task.checkCancellation()
        hasStarted = true

        do {
            let instruments = try await database.loadWatchlist()
            try Task.checkCancellation()
            let cachedQuotes: [InstrumentID: QuoteSnapshot]
            do {
                cachedQuotes = try await database.loadLatestQuotes(for: instruments)
            } catch {
                throw StockWatchStartupError.quoteCacheUnavailable
            }
            try Task.checkCancellation()
            let loadedAlertSettings = try await database.loadAlertSettings()
            try Task.checkCancellation()

            alertConfiguration = loadedAlertSettings.configuration
            priceAlertTargets = loadedAlertSettings.priceTargets
            lastPersistedAlertSettings = loadedAlertSettings
            watchlist = Watchlist(instruments)
            monitoredInstruments = Dictionary(
                uniqueKeysWithValues: instruments.map { instrument in
                    let quote = cachedQuotes[instrument.id]
                    return (
                        instrument.id,
                        MonitoredInstrument(
                            instrument: instrument,
                            quote: quote,
                            status: quote == nil ? .idle : .stale,
                            statusMessage: quote == nil ? nil : tr("本地缓存")
                        )
                    )
                }
            )
            sourceError = nil
        } catch {
            hasStarted = false
            throw error
        }

        restartRefreshLoop()
        scheduleInitialRefresh()
    }

    func stop() async {
        closeOperationAdmission()
        hasStarted = false
        hasStopped = true
        initialRefreshTask?.cancel()
        refreshLoopTask?.cancel()
        refreshCycleTask?.cancel()
        refreshCycleRevision = nil
        clearAllAlerts()
        alertSettingsPersistenceTask?.cancel()

        let initialRefreshTask = initialRefreshTask
        let refreshLoopTask = refreshLoopTask
        let refreshCycleTask = refreshCycleTask
        let alertSettingsPersistenceTask = alertSettingsPersistenceTask
        await initialRefreshTask?.value
        await refreshLoopTask?.value
        await refreshCycleTask?.value
        _ = await alertSettingsPersistenceTask?.value
        self.initialRefreshTask = nil
        self.refreshLoopTask = nil
        self.refreshCycleTask = nil
        await waitForAdmittedOperations()
    }

    @discardableResult
    func shutdown() async -> StockWatchShutdownFailure? {
        if let shutdownTask {
            return await shutdownTask.value
        }
        let task = Task { @MainActor [weak self] in
            await self?.performShutdown()
        }
        shutdownTask = task
        let failure = await task.value
        if failure?.databaseCloseMessage != nil {
            shutdownTask = nil
        }
        return failure
    }

    private func performShutdown() async -> StockWatchShutdownFailure? {
        guard !hasClosedDatabase else { return nil }
        isShuttingDown = true
        closeOperationAdmission()
        await stop()
        await watchlistMutationTail?.value
        let pendingSettingsFlushMessage = await flushPendingPersistenceAdmitted()

        let databaseCloseMessage: String?
        do {
            try await databaseClose(database)
            hasClosedDatabase = true
            databaseCloseMessage = nil
        } catch {
            databaseCloseMessage = error.localizedDescription
        }

        guard pendingSettingsFlushMessage != nil || databaseCloseMessage != nil else {
            return nil
        }
        return StockWatchShutdownFailure(
            databasePath: databasePath,
            pendingSettingsFlushMessage: pendingSettingsFlushMessage,
            databaseCloseMessage: databaseCloseMessage
        )
    }

    func monitoredInstrument(for id: InstrumentID) -> MonitoredInstrument? {
        monitoredInstruments[id]
    }

    func search(_ query: String) async throws -> [Instrument] {
        try await withAdmittedThrowingOperation(.search) {
            try await client.searchInstruments(matching: query)
        }
    }

    @discardableResult
    func remove(_ instrument: Instrument) async -> Bool {
        await withAdmittedOperation(.remove, rejected: false) {
            guard instruments.contains(where: { $0.id == instrument.id }) else { return false }
            return await enqueueWatchlistMutation { [self] in
                var updated = watchlist
                updated.remove(instrument)
                guard updated != watchlist else { return false }

                do {
                    try await database.replaceWatchlist(with: updated.instruments)
                    invalidateRefreshMembership()
                    watchlist = updated
                    monitoredInstruments.removeValue(forKey: instrument.id)
                    alertEvaluators.removeValue(forKey: instrument.id)
                    var updatedTargets = priceAlertTargets
                    updatedTargets.removeValue(forKey: instrument.id)
                    applyPriceAlertTargets(updatedTargets, persist: true)
                    removeAlerts(for: [instrument.id])
                    clearStorageError(context: .watchlist)
                    scheduleRefreshAfterWatchlistMutation()
                    return true
                } catch {
                    recordStorageError(
                        context: .watchlist,
                        message: String(
                            format: tr("保存观察列表失败：%@"),
                            error.localizedDescription
                        )
                    )
                    scheduleRefreshAfterWatchlistMutation()
                    return false
                }
            }
        }
    }

    @discardableResult
    func moveInstruments(from offsets: IndexSet, to destination: Int) async -> Bool {
        await withAdmittedOperation(.move, rejected: false) {
            await enqueueWatchlistMutation { [self] in
                var reordered = watchlist
                reordered.move(from: offsets, to: destination)
                guard reordered != watchlist else { return false }
                do {
                    try await database.replaceWatchlist(with: reordered.instruments)
                    watchlist = reordered
                    clearStorageError(context: .watchlist)
                    return true
                } catch {
                    recordStorageError(
                        context: .watchlist,
                        message: String(
                            format: tr("保存观察列表失败：%@"),
                            error.localizedDescription
                        )
                    )
                    return false
                }
            }
        }
    }

    func watchlistJSONExample() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(instruments),
            let string = String(data: data, encoding: .utf8)
        else { return "[]" }
        return string
    }

    @discardableResult
    func importWatchlist(fromJSON json: String) async -> WatchlistImportResult {
        await withAdmittedOperation(
            .importJSON,
            rejected: .failure(Self.operationUnavailableMessage)
        ) {
            await importWatchlistAdmitted(fromJSON: json)
        }
    }

    private func importWatchlistAdmitted(fromJSON json: String) async -> WatchlistImportResult {
        let trimmed = json.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(tr("请先粘贴 JSON")) }
        guard let data = trimmed.data(using: .utf8) else {
            return .failure(tr("JSON 编码无效"))
        }

        do {
            let payloads = try JSONDecoder().decode(
                [InstrumentImportPayload].self,
                from: data
            )
            var decoded: [Instrument] = []
            decoded.reserveCapacity(payloads.count)
            for (index, payload) in payloads.enumerated() {
                do {
                    decoded.append(
                        try Instrument(
                            validatingSymbol: payload.symbol,
                            name: payload.name,
                            namespace: payload.namespace
                        )
                    )
                } catch {
                    return .failure(
                        String(
                            format: tr("JSON 第 %d 个标的无效：%@"),
                            index + 1,
                            error.localizedDescription
                        )
                    )
                }
            }
            let imported = Watchlist(decoded)
            return await enqueueWatchlistMutation { [self] in
                do {
                    try await database.replaceWatchlist(with: imported.instruments)

                    let keptIDs = Set(imported.instruments.map(\.id))
                    let removedIDs = Set(watchlist.instruments.map(\.id)).subtracting(keptIDs)
                    invalidateRefreshMembership()
                    watchlist = imported
                    monitoredInstruments = Dictionary(
                        uniqueKeysWithValues: imported.instruments.map { instrument in
                            let current = monitoredInstruments[instrument.id]
                            return (
                                instrument.id,
                                MonitoredInstrument(
                                    instrument: instrument,
                                    quote: current?.quote,
                                    status: current?.status ?? .idle,
                                    statusMessage: current?.statusMessage
                                )
                            )
                        }
                    )
                    applyPriceAlertTargets(
                        priceAlertTargets.filter { keptIDs.contains($0.key) },
                        persist: true
                    )
                    alertEvaluators = alertEvaluators.filter { keptIDs.contains($0.key) }
                    removeAlerts(for: removedIDs)
                    clearStorageError(context: .watchlist)
                    scheduleRefreshAfterWatchlistMutation()
                    return .success(count: imported.instruments.count)
                } catch {
                    let message = String(
                        format: tr("保存观察列表失败：%@"),
                        error.localizedDescription
                    )
                    recordStorageError(context: .watchlist, message: message)
                    scheduleRefreshAfterWatchlistMutation()
                    return .failure(message)
                }
            }
        } catch {
            return .failure(
                String(format: tr("JSON 解析失败：%@"), error.localizedDescription)
            )
        }
    }

    @discardableResult
    func add(_ instrument: Instrument) async -> String? {
        await withAdmittedOperation(.add, rejected: Self.operationUnavailableMessage) {
            await enqueueWatchlistMutation { [self] in
                var updated = watchlist
                guard updated.add(instrument) else {
                    return tr("这个标的已经在观察列表中")
                }

                do {
                    try await database.replaceWatchlist(with: updated.instruments)
                    invalidateRefreshMembership()
                    watchlist = updated
                    monitoredInstruments[instrument.id] = MonitoredInstrument(
                        instrument: instrument,
                        quote: nil,
                        status: .idle,
                        statusMessage: nil
                    )
                    clearStorageError(context: .watchlist)
                    scheduleRefreshAfterWatchlistMutation()
                    return nil
                } catch {
                    let message = String(
                        format: tr("保存观察列表失败：%@"),
                        error.localizedDescription
                    )
                    recordStorageError(context: .watchlist, message: message)
                    return message
                }
            }
        }
    }

    @discardableResult
    func refreshAll() async -> Bool {
        await withAdmittedOperation(.refresh, rejected: false) {
            await refreshAllAdmitted()
        }
    }

    private func refreshAllAdmitted() async -> Bool {
        guard hasStarted,
            !hasStopped,
            !isShuttingDown,
            !isClearingQuoteHistory,
            !Task.isCancelled
        else {
            return false
        }
        let revision = watchlistRevision
        if let refreshCycleTask, refreshCycleRevision == revision {
            await refreshCycleTask.value
            return true
        }

        let predecessor = refreshCycleTask
        predecessor?.cancel()
        refreshCycleGeneration += 1
        let generation = refreshCycleGeneration
        let currentInstruments = instruments
        let currentQuotes = Dictionary(
            uniqueKeysWithValues: currentInstruments.compactMap { instrument in
                monitoredInstruments[instrument.id]?.quote.map { (instrument.id, $0) }
            }
        )

        var loadingInstruments = monitoredInstruments
        for instrument in currentInstruments {
            guard var monitored = loadingInstruments[instrument.id] else { continue }
            monitored.status = .loading
            monitored.statusMessage = nil
            loadingInstruments[instrument.id] = monitored
        }
        monitoredInstruments = loadingInstruments

        let coordinator = refreshCoordinator
        let task = Task { [weak self] in
            await predecessor?.value
            guard let self,
                self.hasStarted,
                !self.isShuttingDown,
                !Task.isCancelled,
                self.watchlistRevision == revision
            else { return }
            guard !currentInstruments.isEmpty else {
                self.lastRefresh = Date()
                self.sourceError = nil
                return
            }

            let batch = await coordinator.refresh(
                instruments: currentInstruments,
                currentQuotes: currentQuotes
            )
            guard self.hasStarted,
                !self.isShuttingDown,
                !Task.isCancelled,
                self.watchlistRevision == revision
            else { return }
            self.applyRefreshBatch(batch, expectedCount: currentInstruments.count)
        }
        refreshCycleTask = task
        refreshCycleRevision = revision
        await task.value
        if refreshCycleGeneration == generation {
            refreshCycleTask = nil
            refreshCycleRevision = nil
        }
        return true
    }

    @discardableResult
    func updateAlertConfiguration(_ configuration: AlertConfiguration) -> Bool {
        guard canAdmitOperation, configuration != alertConfiguration else { return false }
        alertConfiguration = configuration
        alertEvaluators.removeAll()
        clearAllAlerts()
        scheduleAlertSettingsPersistence()
        return true
    }

    @discardableResult
    func updatePriceTargets(
        for instrument: Instrument,
        risingPrice: Double?,
        fallingPrice: Double?
    ) -> Bool {
        guard canAdmitOperation else { return false }
        let sanitized = PriceAlertTargets(
            risingPrice: risingPrice.flatMap { $0.isFinite && $0 > 0 ? $0 : nil },
            fallingPrice: fallingPrice.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        )
        var updated = priceAlertTargets
        if sanitized.isEnabled {
            updated[instrument.id] = sanitized
        } else {
            updated.removeValue(forKey: instrument.id)
        }
        applyPriceAlertTargets(updated, persist: true)
        return true
    }

    @discardableResult
    func setPriceTargetsEnabled(for instrument: Instrument, enabled: Bool) -> Bool {
        guard canAdmitOperation else { return false }
        guard enabled else {
            var updated = priceAlertTargets
            updated.removeValue(forKey: instrument.id)
            applyPriceAlertTargets(updated, persist: true)
            return true
        }
        guard let monitored = monitoredInstruments[instrument.id],
            monitored.status == .live,
            let quote = monitored.quote,
            quote.lastPrice > 0
        else { return false }
        return updatePriceTargets(
            for: instrument,
            risingPrice: quote.lastPrice * (1 + alertConfiguration.risingThreshold / 100),
            fallingPrice: quote.lastPrice * (1 - alertConfiguration.fallingThreshold / 100)
        )
    }

    @discardableResult
    func generatePriceTargetsFromCurrentQuotes() async -> Int? {
        await withAdmittedOperation(.generateTargets, rejected: nil) {
            await generatePriceTargetsFromCurrentQuotesAdmitted()
        }
    }

    private func generatePriceTargetsFromCurrentQuotesAdmitted() async -> Int? {
        guard hasStarted, !hasStopped, !isShuttingDown, !Task.isCancelled else {
            return nil
        }
        _ = await refreshAllAdmitted()
        guard hasStarted, !hasStopped, !isShuttingDown, !Task.isCancelled else {
            return nil
        }

        var updated = priceAlertTargets
        var touched = Set<InstrumentID>()
        for instrument in instruments {
            guard !Task.isCancelled else { return nil }
            guard let monitored = monitoredInstruments[instrument.id],
                monitored.status == .live,
                let quote = monitored.quote,
                quote.lastPrice > 0
            else { continue }
            updated[instrument.id] = PriceAlertTargets(
                risingPrice: quote.lastPrice
                    * (1 + alertConfiguration.risingThreshold / 100),
                fallingPrice: quote.lastPrice
                    * (1 - alertConfiguration.fallingThreshold / 100)
            )
            touched.insert(instrument.id)
        }
        guard hasStarted, !hasStopped, !isShuttingDown, !Task.isCancelled else {
            return nil
        }
        applyPriceAlertTargets(updated, persist: true)
        return touched.count
    }

    @discardableResult
    func clearQuoteHistory() async -> Bool {
        await withAdmittedOperation(.clearQuoteHistory, rejected: false) {
            guard !isClearingQuoteHistory else { return false }
            isClearingQuoteHistory = true
            defer { isClearingQuoteHistory = false }

            let refreshTask = refreshCycleTask
            refreshTask?.cancel()
            await refreshTask?.value
            refreshCycleTask = nil
            refreshCycleRevision = nil

            do {
                try await database.clearQuotes()
                quoteBarCount = 0
                monitoredInstruments = monitoredInstruments.mapValues { monitored in
                    var monitored = monitored
                    monitored.status = monitored.quote == nil ? .idle : .stale
                    monitored.statusMessage =
                        monitored.quote == nil
                        ? nil
                        : tr("缓存已清空，等待刷新")
                    return monitored
                }
                clearStorageError(context: .quoteClear)
                clearStorageError(context: .quoteCount)
                return true
            } catch {
                recordStorageError(
                    context: .quoteClear,
                    message: String(
                        format: tr("清空行情缓存失败：%@"),
                        error.localizedDescription
                    )
                )
                return false
            }
        }
    }

    @discardableResult
    func refreshQuoteBarCount() async -> Bool {
        await withAdmittedOperation(.refreshQuoteBarCount, rejected: false) {
            await reloadQuoteBarCount()
        }
    }

    func dismissStorageError() {
        storageErrors.removeAll()
        storageError = nil
    }

    func setAlertDismissalPaused(_ isPaused: Bool) {
        guard isPaused != isAlertDismissalPaused else { return }
        isAlertDismissalPaused = isPaused
        if isPaused {
            if let startedAt = alertDismissalStartedAt,
                let remaining = alertDismissalRemaining
            {
                let elapsed = max(.zero, startedAt.duration(to: alertDismissalNow()))
                alertDismissalRemaining = max(.zero, remaining - elapsed)
            }
            alertDismissalStartedAt = nil
            dismissAlertTask?.cancel()
            dismissAlertTask = nil
        } else {
            scheduleAlertDismissal()
        }
    }

    func dismissActiveAlert() {
        clearActiveAlert()
    }

    func testAlert(_ direction: AlertDirection) {
        let instrument = instruments.first ?? Instrument.initialWatchlist[0]
        let quote = monitoredInstruments[instrument.id]?.quote
        let targets = priceAlertTargets[instrument.id]
        let targetPrice =
            direction == .rising
            ? targets?.risingPrice
            : targets?.fallingPrice
        presentAlert(
            AlertEvent(
                instrument: instrument,
                changePercent: direction == .rising
                    ? alertConfiguration.risingThreshold
                    : -alertConfiguration.fallingThreshold,
                lastPrice: quote?.lastPrice ?? targetPrice ?? 0,
                targetPrice: alertConfiguration.basis == .targetPrice
                    ? targetPrice
                    : nil,
                basis: alertConfiguration.basis,
                direction: direction,
                triggeredAt: Date()
            )
        )
    }

    private func applyRefreshBatch(
        _ batch: QuoteRefreshBatch,
        expectedCount: Int
    ) {
        let interval = Self.signposter.beginInterval(
            "ApplyRefreshBatch",
            id: Self.signposter.makeSignpostID()
        )
        defer { Self.signposter.endInterval("ApplyRefreshBatch", interval) }

        var updatedInstruments = monitoredInstruments
        var acceptedQuotes: [(Instrument, QuoteSnapshot)] = []
        var failures = 0
        var staleResponses = 0
        var storageFailure: String?
        var didPersistQuote = false

        for outcome in batch.outcomes {
            guard var monitored = updatedInstruments[outcome.instrument.id] else {
                continue
            }
            switch outcome.result {
            case .updated(let quote, let error):
                monitored = MonitoredInstrument(
                    instrument: outcome.instrument,
                    quote: quote,
                    status: .live,
                    statusMessage: nil
                )
                acceptedQuotes.append((outcome.instrument, quote))
                storageFailure = storageFailure ?? error
                didPersistQuote = true
            case .cached(let quote, let message, let error):
                staleResponses += 1
                monitored = MonitoredInstrument(
                    instrument: outcome.instrument,
                    quote: quote,
                    status: .stale,
                    statusMessage: message
                )
                storageFailure = storageFailure ?? error
                didPersistQuote = true
            case .noData(let message):
                monitored.status = monitored.quote == nil ? .idle : .stale
                monitored.statusMessage = message
            case .stale(let message):
                staleResponses += 1
                monitored.status = .stale
                monitored.statusMessage = message
            case .failed(let message):
                failures += 1
                monitored.status = monitored.quote == nil ? .idle : .stale
                monitored.statusMessage = message
            case .rejected(let message):
                monitored.status = monitored.quote == nil ? .idle : .stale
                monitored.statusMessage = message
            case .discarded:
                failures += 1
                monitored.status = monitored.quote == nil ? .idle : .stale
                monitored.statusMessage = nil
            }
            updatedInstruments[outcome.instrument.id] = monitored
        }
        monitoredInstruments = updatedInstruments

        for (instrument, quote) in acceptedQuotes {
            evaluateAlert(for: instrument, quote: quote)
        }
        if let storageFailure {
            recordStorageError(
                context: .quoteWrite,
                message: String(
                    format: tr("行情已更新，但写入本地数据库失败：%@"),
                    storageFailure
                )
            )
        } else if didPersistQuote {
            clearStorageError(context: .quoteWrite)
        }

        lastRefresh = Date()
        if failures == expectedCount {
            sourceError = tr("行情连接暂不可用，已保留上次成功数据")
        } else if failures + staleResponses == expectedCount {
            sourceError = tr("行情源暂未返回更新数据，已保留较新缓存")
        } else {
            sourceError = nil
        }
    }

    private func evaluateAlert(for instrument: Instrument, quote: QuoteSnapshot) {
        guard alertConfiguration.isEnabled,
            let rule = alertConfiguration.rule(
                targets: priceAlertTargets[instrument.id]
            )
        else {
            alertEvaluators.removeValue(forKey: instrument.id)
            return
        }

        var evaluator = alertEvaluators[instrument.id] ?? AlertEvaluator()
        let direction = evaluator.evaluate(
            changePercent: quote.changePercent,
            lastPrice: quote.lastPrice,
            rule: rule
        )
        alertEvaluators[instrument.id] = evaluator
        guard let direction else { return }

        let targets = priceAlertTargets[instrument.id]
        let targetPrice: Double?
        switch (alertConfiguration.basis, direction) {
        case (.targetPrice, .rising): targetPrice = targets?.risingPrice
        case (.targetPrice, .falling): targetPrice = targets?.fallingPrice
        case (.percentage, _): targetPrice = nil
        }
        presentAlert(
            AlertEvent(
                instrument: instrument,
                changePercent: quote.changePercent,
                lastPrice: quote.lastPrice,
                targetPrice: targetPrice,
                basis: alertConfiguration.basis,
                direction: direction,
                triggeredAt: Date()
            )
        )
    }

    private func presentAlert(_ alert: AlertEvent) {
        guard activeAlert == nil else {
            pendingAlerts.append(alert)
            return
        }
        showAlert(alert)
    }

    private func showAlert(_ alert: AlertEvent) {
        activeAlert = alert
        alertDismissalRemaining = alertDismissalDelay
        alertDismissalStartedAt = nil
        let soundEnabled =
            alert.direction == .rising
            ? preferences.bullSoundEnabled
            : preferences.bearSoundEnabled
        alertSoundPlayer.play(alert.direction, isEnabled: soundEnabled)
        scheduleAlertDismissal()
    }

    private func scheduleAlertDismissal() {
        dismissAlertTask?.cancel()
        dismissAlertTask = nil
        alertDismissalStartedAt = nil
        guard let alertID = activeAlert?.id,
            !isAlertDismissalPaused,
            let remaining = alertDismissalRemaining
        else { return }
        guard remaining > .zero else {
            clearActiveAlert()
            return
        }
        alertDismissalStartedAt = alertDismissalNow()
        let sleep = alertDismissalSleep
        dismissAlertTask = Task { [weak self] in
            do {
                try await sleep(remaining)
            } catch {
                return
            }
            guard !Task.isCancelled, self?.activeAlert?.id == alertID else { return }
            self?.clearActiveAlert()
        }
    }

    private func clearActiveAlert() {
        activeAlert = nil
        dismissAlertTask?.cancel()
        dismissAlertTask = nil
        isAlertDismissalPaused = false
        alertDismissalRemaining = nil
        alertDismissalStartedAt = nil
        alertSoundPlayer.stop()

        guard !pendingAlerts.isEmpty else { return }
        showAlert(pendingAlerts.removeFirst())
    }

    private func clearAllAlerts() {
        pendingAlerts.removeAll()
        activeAlert = nil
        dismissAlertTask?.cancel()
        dismissAlertTask = nil
        isAlertDismissalPaused = false
        alertDismissalRemaining = nil
        alertDismissalStartedAt = nil
        alertSoundPlayer.stop()
    }

    private func removeAlerts(for instrumentIDs: Set<InstrumentID>) {
        guard !instrumentIDs.isEmpty else { return }
        pendingAlerts.removeAll { instrumentIDs.contains($0.instrument.id) }
        guard let activeID = activeAlert?.instrument.id,
            instrumentIDs.contains(activeID)
        else { return }
        clearActiveAlert()
    }

    private func applyPriceAlertTargets(
        _ targets: [InstrumentID: PriceAlertTargets],
        persist: Bool
    ) {
        guard targets != priceAlertTargets else { return }
        let changedIDs = Set(priceAlertTargets.keys)
            .union(targets.keys)
            .filter { priceAlertTargets[$0] != targets[$0] }
        priceAlertTargets = targets
        for id in changedIDs {
            alertEvaluators.removeValue(forKey: id)
        }
        removeAlerts(for: Set(changedIDs))
        if persist {
            scheduleAlertSettingsPersistence()
        }
    }

    @discardableResult
    func flushPendingPersistence() async -> String? {
        await withAdmittedOperation(
            .flushPersistence,
            rejected: Self.operationUnavailableMessage
        ) {
            await flushPendingPersistenceAdmitted()
        }
    }

    private func flushPendingPersistenceAdmitted() async -> String? {
        var persistenceFailure: String?
        while true {
            alertSettingsRevision += 1
            let revision = alertSettingsRevision
            let predecessor = alertSettingsPersistenceTask
            alertSettingsPersistenceTask = nil
            predecessor?.cancel()
            #if DEBUG || STOCKWATCH_BENCHMARK
                if let predecessor {
                    await alertSettingsPersistenceEventObserverForTesting?(
                        .flushAwaitingLineage(currentAlertSettings, revision)
                    )
                    persistenceFailure = await predecessor.value ?? persistenceFailure
                }
            #else
                if let predecessor {
                    persistenceFailure = await predecessor.value ?? persistenceFailure
                }
            #endif

            guard alertSettingsPersistenceTask == nil else { continue }
            let snapshot = currentAlertSettings
            guard snapshot != lastPersistedAlertSettings else {
                return persistenceFailure
            }
            persistenceFailure =
                await persistAlertSettings(snapshot, revision: revision)
                ?? persistenceFailure
        }
    }

    private var currentAlertSettings: AlertSettingsSnapshot {
        AlertSettingsSnapshot(
            configuration: alertConfiguration,
            priceTargets: priceAlertTargets
        )
    }

    private func scheduleAlertSettingsPersistence() {
        alertSettingsRevision += 1
        let revision = alertSettingsRevision
        let snapshot = currentAlertSettings
        let predecessor = alertSettingsPersistenceTask
        predecessor?.cancel()
        alertSettingsPersistenceTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(250))
            } catch {
                // A replacement still drains its predecessor before exiting.
            }
            _ = await predecessor?.value
            guard let self,
                !Task.isCancelled,
                revision == self.alertSettingsRevision
            else {
                return nil
            }
            return await self.persistAlertSettings(
                snapshot,
                revision: revision,
                reportsScheduledCompletion: true
            )
        }
    }

    private func persistAlertSettings(
        _ snapshot: AlertSettingsSnapshot,
        revision: Int,
        reportsScheduledCompletion: Bool = false
    ) async -> String? {
        do {
            try await database.saveAlertSettings(snapshot)
            #if DEBUG || STOCKWATCH_BENCHMARK
                await alertSettingsPersistenceEventObserverForTesting?(
                    .committed(snapshot, revision)
                )
            #endif
            if revision >= lastPersistedAlertSettingsRevision {
                lastPersistedAlertSettings = snapshot
                lastPersistedAlertSettingsRevision = revision
            }
            guard revision == alertSettingsRevision else {
                #if DEBUG || STOCKWATCH_BENCHMARK
                    if reportsScheduledCompletion {
                        await alertSettingsPersistenceEventObserverForTesting?(
                            .finished(snapshot, revision)
                        )
                    }
                #endif
                return nil
            }
            alertSettingsPersistenceTask = nil
            clearStorageError(context: .alertSettings)
            #if DEBUG || STOCKWATCH_BENCHMARK
                if reportsScheduledCompletion {
                    await alertSettingsPersistenceEventObserverForTesting?(
                        .finished(snapshot, revision)
                    )
                }
            #endif
            return nil
        } catch {
            guard revision == alertSettingsRevision else { return nil }
            let observedIDs = Set(instruments.map(\.id))
            alertConfiguration = lastPersistedAlertSettings.configuration
            priceAlertTargets = lastPersistedAlertSettings.priceTargets.filter {
                observedIDs.contains($0.key)
            }
            alertEvaluators.removeAll()
            clearAllAlerts()
            alertSettingsPersistenceTask = nil
            recordStorageError(
                context: .alertSettings,
                message: String(
                    format: tr("提醒设置保存失败，已恢复上次保存值：%@"),
                    error.localizedDescription
                )
            )
            return error.localizedDescription
        }
    }

    private static var operationUnavailableMessage: String {
        MonitorStoreOperationError.unavailable.localizedDescription
    }

    private var canAdmitOperation: Bool {
        acceptsOperations
            && hasStarted
            && !hasStopped
            && !isShuttingDown
            && !hasClosedDatabase
    }

    private func withAdmittedOperation<Result>(
        _ operationKind: MonitorStoreOperation,
        rejected: Result,
        requiresStarted: Bool = true,
        operation: @MainActor () async -> Result
    ) async -> Result {
        guard beginOperationAdmission(requiresStarted: requiresStarted) else {
            return rejected
        }
        defer { finishOperationAdmission() }
        #if DEBUG || STOCKWATCH_BENCHMARK
            await operationAdmissionObserverForTesting?(operationKind)
        #endif
        return await operation()
    }

    private func withAdmittedThrowingOperation<Result>(
        _ operationKind: MonitorStoreOperation,
        requiresStarted: Bool = true,
        operation: @MainActor () async throws -> Result
    ) async throws -> Result {
        guard beginOperationAdmission(requiresStarted: requiresStarted) else {
            throw MonitorStoreOperationError.unavailable
        }
        defer { finishOperationAdmission() }
        #if DEBUG || STOCKWATCH_BENCHMARK
            await operationAdmissionObserverForTesting?(operationKind)
        #endif
        return try await operation()
    }

    private func beginOperationAdmission(requiresStarted: Bool) -> Bool {
        guard acceptsOperations,
            !hasStopped,
            !isShuttingDown,
            !hasClosedDatabase,
            !Task.isCancelled,
            !requiresStarted || hasStarted
        else { return false }
        admittedOperationCount += 1
        return true
    }

    private func finishOperationAdmission() {
        precondition(admittedOperationCount > 0)
        admittedOperationCount -= 1
        guard admittedOperationCount == 0 else { return }
        let waiters = admittedOperationDrainWaiters
        admittedOperationDrainWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }

    private func closeOperationAdmission() {
        acceptsOperations = false
    }

    private func waitForAdmittedOperations() async {
        guard admittedOperationCount > 0 else { return }
        await withCheckedContinuation { continuation in
            admittedOperationDrainWaiters.append(continuation)
        }
    }

    private func enqueueWatchlistMutation<Result: Sendable>(
        _ operation: @escaping @MainActor @Sendable () async -> Result
    ) async -> Result {
        pendingWatchlistMutations += 1
        isWatchlistMutating = true
        let previousTask = watchlistMutationTail
        let operationTask = Task { @MainActor in
            await previousTask?.value
            return await operation()
        }
        watchlistMutationTail = Task { @MainActor in
            _ = await operationTask.value
        }

        let result = await operationTask.value
        pendingWatchlistMutations -= 1
        isWatchlistMutating = pendingWatchlistMutations > 0
        return result
    }

    private func invalidateRefreshMembership() {
        watchlistRevision += 1
        refreshCycleTask?.cancel()
        refreshCycleRevision = nil
    }

    private func scheduleRefreshAfterWatchlistMutation() {
        guard hasStarted, !isShuttingDown else { return }
        Task { [weak self] in
            await self?.refreshAll()
        }
    }

    private func scheduleInitialRefresh() {
        let predecessor = initialRefreshTask
        predecessor?.cancel()
        initialRefreshGeneration += 1
        let generation = initialRefreshGeneration
        initialRefreshTask = Task { [weak self] in
            await predecessor?.value
            guard let self,
                self.hasStarted,
                !self.isShuttingDown,
                !Task.isCancelled
            else { return }
            await self.refreshAll()
            guard !Task.isCancelled,
                generation == self.initialRefreshGeneration
            else { return }
            self.initialRefreshTask = nil
        }
    }

    private func reloadQuoteBarCount() async -> Bool {
        do {
            quoteBarCount = try await database.quoteBarCount()
            clearStorageError(context: .quoteCount)
            return true
        } catch {
            recordStorageError(
                context: .quoteCount,
                message: String(
                    format: tr("读取缓存分钟数失败：%@"),
                    error.localizedDescription
                )
            )
            return false
        }
    }

    private func recordStorageError(
        context: StorageErrorContext,
        message: String
    ) {
        storageErrorRevision += 1
        storageErrors[context] = StorageErrorEntry(
            message: message,
            revision: storageErrorRevision
        )
        publishLatestStorageError()
    }

    private func clearStorageError(context: StorageErrorContext) {
        guard storageErrors.removeValue(forKey: context) != nil else { return }
        publishLatestStorageError()
    }

    private func publishLatestStorageError() {
        storageError =
            storageErrors.values.max {
                $0.revision < $1.revision
            }?.message
    }

    private func restartRefreshLoop() {
        guard hasStarted, !isShuttingDown else { return }
        let predecessor = refreshLoopTask
        predecessor?.cancel()
        refreshLoopGeneration += 1
        let generation = refreshLoopGeneration
        refreshLoopTask = Task { [weak self] in
            await predecessor?.value
            guard let self,
                self.hasStarted,
                !self.isShuttingDown,
                !Task.isCancelled
            else { return }
            while self.hasStarted, !self.isShuttingDown, !Task.isCancelled {
                let seconds = self.preferences.refreshInterval
                do {
                    try await Task.sleep(for: .seconds(seconds))
                } catch {
                    break
                }
                guard self.hasStarted,
                    !self.isShuttingDown,
                    !Task.isCancelled
                else { break }
                await self.refreshAll()
            }
            guard generation == self.refreshLoopGeneration else { return }
            self.refreshLoopTask = nil
        }
    }

    private struct StorageErrorEntry {
        let message: String
        let revision: Int
    }

    private enum StorageErrorContext: Hashable {
        case watchlist
        case quoteWrite
        case quoteCount
        case quoteClear
        case alertSettings
    }

    private struct InstrumentImportPayload: Decodable {
        let symbol: String
        let name: String
        let namespace: SymbolNamespace
    }
}
