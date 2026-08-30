import Combine
import Foundation

struct StockWatchShutdownFailure: Error, Equatable, Sendable {
    let databasePath: String
    let pendingSettingsFlushMessage: String?
    let databaseCloseMessage: String?

    var message: String {
        var messages: [String] = []
        if pendingSettingsFlushMessage != nil {
            messages.append(tr("关闭前保存提醒设置失败。"))
        }
        if databaseCloseMessage != nil {
            messages.append(tr("关闭本地行情数据库失败。请重试关闭。"))
        }
        return messages.joined(separator: "\n")
    }
}

struct StockWatchStartupFailure: Equatable, Sendable {
    let message: String
    let databasePath: String
    let shutdownFailure: StockWatchShutdownFailure?

    init(
        message: String,
        databasePath: String,
        shutdownFailure: StockWatchShutdownFailure? = nil
    ) {
        self.message = message
        self.databasePath = databasePath
        self.shutdownFailure = shutdownFailure
    }
}

@MainActor
final class StockWatchLifecycleCoordinator {
    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Void, Never>
    }

    private var activeLeaseID: UUID?
    private var waiters: [Waiter] = []
    private var retainedFailure: StockWatchShutdownFailure?
    private var retainedRecovery: (@MainActor () async -> StockWatchShutdownFailure?)?

    func acquire() async -> UUID? {
        let id = UUID()
        if activeLeaseID == nil {
            activeLeaseID = id
        } else {
            await withCheckedContinuation { continuation in
                waiters.append(Waiter(id: id, continuation: continuation))
            }
        }

        guard !Task.isCancelled else {
            release(id)
            return nil
        }
        return id
    }

    func failureForMount(
        leaseID: UUID,
        retrying: Bool
    ) async -> StockWatchShutdownFailure? {
        guard activeLeaseID == leaseID else { return retainedFailure }
        guard retrying, retainedFailure != nil else { return retainedFailure }

        if let retainedRecovery {
            let retryFailure = await retainedRecovery()
            retainedFailure = retryFailure
            self.retainedRecovery =
                retryFailure?.databaseCloseMessage == nil
                ? nil
                : retainedRecovery
        } else {
            retainedFailure = nil
        }
        return retainedFailure
    }

    func finishMount(
        leaseID: UUID,
        store: MonitorStore
    ) async -> StockWatchShutdownFailure? {
        let failure = await store.shutdown()
        if let failure {
            retainedFailure = failure
            if failure.databaseCloseMessage != nil {
                retainedRecovery = { await store.shutdown() }
            } else {
                retainedRecovery = nil
            }
        }
        release(leaseID)
        return failure
    }

    func finishOpenedDatabase(
        leaseID: UUID,
        database: MarketDatabase,
        databasePath: String,
        close: @escaping @Sendable (MarketDatabase) async throws -> Void
    ) async -> StockWatchShutdownFailure? {
        let failure = await Self.closeFailure(
            database: database,
            databasePath: databasePath,
            close: close
        )
        if let failure {
            retainedFailure = failure
            retainedRecovery = {
                await Self.closeFailure(
                    database: database,
                    databasePath: databasePath,
                    close: close
                )
            }
        }
        release(leaseID)
        return failure
    }

    func release(_ leaseID: UUID) {
        guard activeLeaseID == leaseID else { return }
        guard !waiters.isEmpty else {
            activeLeaseID = nil
            return
        }
        let waiter = waiters.removeFirst()
        activeLeaseID = waiter.id
        waiter.continuation.resume()
    }

    private static func closeFailure(
        database: MarketDatabase,
        databasePath: String,
        close: @Sendable (MarketDatabase) async throws -> Void
    ) async -> StockWatchShutdownFailure? {
        do {
            try await close(database)
            return nil
        } catch {
            return StockWatchShutdownFailure(
                databasePath: databasePath,
                pendingSettingsFlushMessage: nil,
                databaseCloseMessage: error.localizedDescription
            )
        }
    }
}

@MainActor
struct StockWatchMountedRun {
    let store: MonitorStore
    let preferences: StockWatchPreferences
}

@MainActor
final class StockWatchBootstrap: ObservableObject {
    @Published private(set) var mountedRun: StockWatchMountedRun?
    @Published private(set) var failure: StockWatchStartupFailure?
    @Published private(set) var isStarting = false

    var store: MonitorStore? { mountedRun?.store }
    var preferences: StockWatchPreferences? { mountedRun?.preferences }

    private let lifecycleCoordinator: StockWatchLifecycleCoordinator
    private let preferencesFactory: @MainActor () -> StockWatchPreferences
    private let client: any MarketDataClient
    private let alertSoundPlayer: any AlertSoundPlaying
    private let databasePath: String
    private let databaseFactory: @Sendable () async throws -> MarketDatabase
    private let databaseClose: @Sendable (MarketDatabase) async throws -> Void
    private let retryRequests: AsyncStream<Void>
    private let retryContinuation: AsyncStream<Void>.Continuation
    private var leaseID: UUID?
    private var isRunning = false

    convenience init(
        platform: any StockWatchPlatformClient,
        lifecycleCoordinator: StockWatchLifecycleCoordinator,
        preferencesFactory: @escaping @MainActor () -> StockWatchPreferences = {
            StockWatchPreferences()
        },
        client: any MarketDataClient = PublicMarketDataClient(),
        storage: StockWatchStorage = StockWatchStorage()
    ) {
        self.init(
            lifecycleCoordinator: lifecycleCoordinator,
            preferencesFactory: preferencesFactory,
            client: client,
            alertSoundPlayer: AlertSoundPlayer(platform: platform),
            databasePath: storage.databasePath,
            databaseFactory: { try await storage.open() }
        )
    }

    init(
        lifecycleCoordinator: StockWatchLifecycleCoordinator = StockWatchLifecycleCoordinator(),
        preferencesFactory: @escaping @MainActor () -> StockWatchPreferences,
        client: any MarketDataClient = PublicMarketDataClient(),
        alertSoundPlayer: any AlertSoundPlaying = NoOpAlertSoundPlayer(),
        databasePath: String,
        databaseFactory: @escaping @Sendable () async throws -> MarketDatabase,
        databaseClose: @escaping @Sendable (MarketDatabase) async throws -> Void = {
            try $0.close()
        }
    ) {
        self.lifecycleCoordinator = lifecycleCoordinator
        self.preferencesFactory = preferencesFactory
        self.client = client
        self.alertSoundPlayer = alertSoundPlayer
        self.databasePath = databasePath
        self.databaseFactory = databaseFactory
        self.databaseClose = databaseClose
        (retryRequests, retryContinuation) = AsyncStream.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
    }

    func run() async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }

        await start()
        for await _ in retryRequests {
            guard !Task.isCancelled else { break }
            guard mountedRun == nil else { continue }
            await start(retryingShutdownFailure: true)
        }

        await shutdown()
    }

    func start(retryingShutdownFailure: Bool = false) async {
        guard mountedRun == nil, !isStarting, !Task.isCancelled else { return }
        isStarting = true
        failure = nil
        defer { isStarting = false }

        if leaseID == nil {
            leaseID = await lifecycleCoordinator.acquire()
        }
        guard let leaseID else { return }
        guard !Task.isCancelled else {
            lifecycleCoordinator.release(leaseID)
            self.leaseID = nil
            return
        }

        if let shutdownFailure = await lifecycleCoordinator.failureForMount(
            leaseID: leaseID,
            retrying: retryingShutdownFailure
        ) {
            guard !Task.isCancelled else {
                lifecycleCoordinator.release(leaseID)
                self.leaseID = nil
                return
            }
            failure = StockWatchStartupFailure(
                message: shutdownFailure.message,
                databasePath: shutdownFailure.databasePath,
                shutdownFailure: shutdownFailure
            )
            return
        }
        guard !Task.isCancelled else {
            lifecycleCoordinator.release(leaseID)
            self.leaseID = nil
            return
        }

        var openedDatabase: MarketDatabase?
        var candidate: MonitorStore?
        do {
            let database = try await databaseFactory()
            openedDatabase = database
            try Task.checkCancellation()

            let preferences = preferencesFactory()
            try Task.checkCancellation()
            let newStore = MonitorStore(
                client: client,
                database: database,
                preferences: preferences,
                alertSoundPlayer: alertSoundPlayer,
                databaseClose: databaseClose
            )
            candidate = newStore
            try await newStore.start()
            try Task.checkCancellation()
            mountedRun = StockWatchMountedRun(
                store: newStore,
                preferences: preferences
            )
        } catch {
            let cleanupFailure: StockWatchShutdownFailure?
            if let candidate {
                cleanupFailure = await lifecycleCoordinator.finishMount(
                    leaseID: leaseID,
                    store: candidate
                )
            } else if let openedDatabase {
                cleanupFailure = await lifecycleCoordinator.finishOpenedDatabase(
                    leaseID: leaseID,
                    database: openedDatabase,
                    databasePath: databasePath,
                    close: databaseClose
                )
            } else {
                lifecycleCoordinator.release(leaseID)
                cleanupFailure = nil
            }
            self.leaseID = nil
            mountedRun = nil
            guard !Task.isCancelled else { return }
            if let cleanupFailure {
                failure = StockWatchStartupFailure(
                    message: cleanupFailure.message,
                    databasePath: cleanupFailure.databasePath,
                    shutdownFailure: cleanupFailure
                )
            } else {
                failure = StockWatchStartupFailure(
                    message: Self.safeStartupMessage(for: error),
                    databasePath: (error as? StockWatchStorageError)?.recoveryDatabasePath
                        ?? databasePath
                )
            }
        }
    }

    private static func safeStartupMessage(for error: Error) -> String {
        if error is StockWatchStorageError {
            return tr("无法安全导入独立 MarketSprite 数据库。请检查旧应用已完全退出且数据库有效。")
        }
        if let databaseError = error as? MarketDatabaseError {
            switch databaseError {
            case .applicationSupportUnavailable:
                return tr("无法访问应用支持目录")
            default:
                return tr("股票看盘数据库无效，无法安全打开。")
            }
        }
        return tr("无法打开股票看盘数据库。请检查文件权限或磁盘空间后重试。")
    }

    func requestRetry() {
        guard mountedRun == nil, failure != nil, !isStarting else { return }
        retryContinuation.yield()
    }

    @discardableResult
    func shutdown() async -> StockWatchShutdownFailure? {
        let run = mountedRun
        mountedRun = nil
        guard let leaseID else { return nil }
        self.leaseID = nil

        if let run {
            return await lifecycleCoordinator.finishMount(
                leaseID: leaseID,
                store: run.store
            )
        }
        lifecycleCoordinator.release(leaseID)
        return nil
    }
}
