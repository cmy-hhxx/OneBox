import Foundation
import GRDB

private struct LegacyDatabaseRequiresRecovery: LocalizedError, Sendable {
    var errorDescription: String? {
        "检测到 WAL、共享内存或未完成的回滚日志。请完全退出 MarketSprite，确认数据库已 checkpoint 并切回非 WAL 模式后再重试。"
    }
}

#if DEBUG || STOCKWATCH_BENCHMARK
    enum StockWatchStorageImportStage: Sendable {
        case snapshotCopied
    }
#endif

enum StockWatchStorageError: LocalizedError, Equatable, Sendable {
    case legacyImportFailed(path: String, reason: String)

    var recoveryDatabasePath: String {
        switch self {
        case .legacyImportFailed(let path, _):
            path
        }
    }

    var errorDescription: String? {
        switch self {
        case .legacyImportFailed(_, let reason):
            "无法导入独立 MarketSprite 数据库：\(reason)"
        }
    }
}

struct StockWatchStorage: Sendable {
    private static let databaseFileName = "marketsprite.sqlite"
    private static let backupPagesPerStep: CInt = 32

    let applicationSupportDirectory: URL?
    #if DEBUG || STOCKWATCH_BENCHMARK
        private let importStageObserverForTesting:
            (@Sendable (StockWatchStorageImportStage) async -> Void)?
        private let databaseOpenerForTesting: (@Sendable (URL) throws -> MarketDatabase)?
    #endif

    init(fileManager: FileManager = .default) {
        applicationSupportDirectory =
            fileManager.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first
        #if DEBUG || STOCKWATCH_BENCHMARK
            importStageObserverForTesting = nil
            databaseOpenerForTesting = nil
        #endif
    }

    #if DEBUG || STOCKWATCH_BENCHMARK
        init(
            applicationSupportDirectory: URL,
            importStageObserverForTesting:
                (@Sendable (StockWatchStorageImportStage) async -> Void)? = nil,
            databaseOpenerForTesting: (@Sendable (URL) throws -> MarketDatabase)? = nil
        ) {
            self.applicationSupportDirectory = applicationSupportDirectory
            self.importStageObserverForTesting = importStageObserverForTesting
            self.databaseOpenerForTesting = databaseOpenerForTesting
        }
    #else
        init(applicationSupportDirectory: URL) {
            self.applicationSupportDirectory = applicationSupportDirectory
        }
    #endif

    var databaseURL: URL? {
        applicationSupportDirectory?
            .appendingPathComponent("OneBox", isDirectory: true)
            .appendingPathComponent("StockWatch", isDirectory: true)
            .appendingPathComponent(Self.databaseFileName, isDirectory: false)
    }

    var databasePath: String {
        databaseURL?.path ?? ""
    }

    private var legacyDatabaseURL: URL? {
        applicationSupportDirectory?
            .appendingPathComponent("MarketSprite", isDirectory: true)
            .appendingPathComponent(Self.databaseFileName, isDirectory: false)
    }

    @concurrent
    func open() async throws -> MarketDatabase {
        try Task.checkCancellation()
        let cancellationToken = DatabaseCancellationToken()
        return try await withTaskCancellationHandler {
            try cancellationToken.checkCancellation()
            return try await open(cancellationToken: cancellationToken)
        } onCancel: {
            cancellationToken.cancel()
        }
    }

    private func open(
        cancellationToken: DatabaseCancellationToken
    ) async throws -> MarketDatabase {
        guard let databaseURL, let legacyDatabaseURL else {
            throw MarketDatabaseError.applicationSupportUnavailable
        }
        let fileManager = FileManager.default
        let canonicalExistedAtEntry = fileManager.fileExists(atPath: databaseURL.path)
        let directory = databaseURL.deletingLastPathComponent()
        var importedLegacyDatabase = false
        var ownsCanonicalDatabase = false

        do {
            try cancellationToken.checkCancellation()
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try cancellationToken.checkCancellation()

            if !canonicalExistedAtEntry,
                fileManager.fileExists(atPath: legacyDatabaseURL.path)
            {
                do {
                    importedLegacyDatabase = try await importLegacyDatabase(
                        from: legacyDatabaseURL,
                        to: databaseURL,
                        in: directory,
                        cancellationToken: cancellationToken
                    )
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    throw StockWatchStorageError.legacyImportFailed(
                        path: legacyDatabaseURL.path,
                        reason: error.localizedDescription
                    )
                }
            }

            try cancellationToken.checkCancellation()
            ownsCanonicalDatabase =
                importedLegacyDatabase
                || !fileManager.fileExists(atPath: databaseURL.path)
            #if DEBUG || STOCKWATCH_BENCHMARK
                let database =
                    try databaseOpenerForTesting?(databaseURL)
                    ?? MarketDatabase.openInDirectory(
                        directory,
                        fileName: Self.databaseFileName,
                        fileManager: fileManager,
                        cancellationToken: cancellationToken
                    )
            #else
                let database = try MarketDatabase.openInDirectory(
                    directory,
                    fileName: Self.databaseFileName,
                    fileManager: fileManager,
                    cancellationToken: cancellationToken
                )
            #endif
            do {
                try cancellationToken.checkCancellation()
                return database
            } catch {
                try? await database.close()
                throw error
            }
        } catch {
            if ownsCanonicalDatabase {
                Self.removeDatabaseFiles(at: databaseURL, fileManager: fileManager)
            }
            throw error
        }
    }

    @concurrent
    func clearQuoteCache() async throws {
        let cancellationToken = DatabaseCancellationToken()
        try await withTaskCancellationHandler {
            try await clearQuoteCache(cancellationToken: cancellationToken)
        } onCancel: {
            cancellationToken.cancel()
        }
    }

    @concurrent
    private func clearQuoteCache(
        cancellationToken: DatabaseCancellationToken
    ) async throws {
        guard let databaseURL else {
            throw MarketDatabaseError.applicationSupportUnavailable
        }
        try cancellationToken.checkCancellation()
        guard FileManager.default.fileExists(atPath: databaseURL.path) else {
            throw CocoaError(.fileNoSuchFile)
        }

        let database = try MarketDatabase.open(
            atPath: databaseURL.path,
            cancellationToken: cancellationToken
        )
        do {
            try cancellationToken.checkCancellation()
            try await database.clearQuotes()
            try cancellationToken.checkCancellation()
            try await database.close()
        } catch {
            try? await database.close()
            throw error
        }
    }

    private func importLegacyDatabase(
        from legacyURL: URL,
        to databaseURL: URL,
        in directory: URL,
        cancellationToken: DatabaseCancellationToken
    ) async throws -> Bool {
        let fileManager = FileManager.default
        try cancellationToken.checkCancellation()
        try Self.validateLegacySourceCanBeOpened(at: legacyURL, fileManager: fileManager)
        try cancellationToken.checkCancellation()
        try await Self.validateDatabase(
            at: legacyURL,
            cancellationToken: cancellationToken
        )
        try cancellationToken.checkCancellation()

        let temporaryURL = directory.appendingPathComponent(
            ".marketsprite.sqlite.importing-\(UUID().uuidString)",
            isDirectory: false
        )
        defer {
            Self.removeDatabaseFiles(at: temporaryURL, fileManager: fileManager)
        }

        try Self.validateLegacySourceCanBeOpened(at: legacyURL, fileManager: fileManager)
        try cancellationToken.checkCancellation()
        try Self.copyDatabaseSnapshot(
            from: legacyURL,
            to: temporaryURL,
            cancellationToken: cancellationToken
        )
        #if DEBUG || STOCKWATCH_BENCHMARK
            await importStageObserverForTesting?(.snapshotCopied)
        #endif
        try cancellationToken.checkCancellation()
        try await Self.validateDatabase(
            at: temporaryURL,
            cancellationToken: cancellationToken
        )
        try cancellationToken.checkCancellation()

        guard !fileManager.fileExists(atPath: databaseURL.path) else {
            return false
        }
        try cancellationToken.checkCancellation()
        try fileManager.moveItem(at: temporaryURL, to: databaseURL)
        return true
    }

    private static func copyDatabaseSnapshot(
        from sourceURL: URL,
        to targetURL: URL,
        cancellationToken: DatabaseCancellationToken
    ) throws {
        var sourceConfiguration = Configuration()
        sourceConfiguration.readonly = true
        let source = try DatabaseQueue(
            path: sourceURL.path,
            configuration: sourceConfiguration
        )
        defer { try? source.close() }

        let target = try DatabaseQueue(path: targetURL.path)
        defer { try? target.close() }

        try source.backup(
            to: target,
            pagesPerStep: backupPagesPerStep
        ) { progress in
            if !progress.isCompleted {
                try cancellationToken.checkCancellation()
            }
        }
        try cancellationToken.checkCancellation()
        try target.close()
        try source.close()
    }

    private static func validateDatabase(
        at url: URL,
        cancellationToken: DatabaseCancellationToken
    ) async throws {
        try cancellationToken.checkCancellation()
        let database = try MarketDatabase.openReadOnly(
            atPath: url.path,
            cancellationToken: cancellationToken
        )
        do {
            try cancellationToken.checkCancellation()
            let instruments = try await database.loadWatchlist()
            try cancellationToken.checkCancellation()
            try await database.validateLatestQuotes(for: instruments)
            try cancellationToken.checkCancellation()
            _ = try await database.loadAlertSettings()
            try cancellationToken.checkCancellation()
            try await database.close()
        } catch {
            try? await database.close()
            if cancellationToken.isCancelled {
                throw CancellationError()
            }
            throw error
        }
    }

    private static func validateLegacySourceCanBeOpened(
        at url: URL,
        fileManager: FileManager
    ) throws {
        for suffix in ["-wal", "-shm"]
        where fileManager.fileExists(atPath: url.path + suffix) {
            throw LegacyDatabaseRequiresRecovery()
        }

        let journalPath = url.path + "-journal"
        if fileManager.fileExists(atPath: journalPath) {
            let attributes = try fileManager.attributesOfItem(atPath: journalPath)
            let size = (attributes[.size] as? NSNumber)?.int64Value ?? 1
            if size > 0 {
                throw LegacyDatabaseRequiresRecovery()
            }
        }

        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let header = try handle.read(upToCount: 20) ?? Data()
        let sqliteMagic = Data("SQLite format 3\0".utf8)
        if header.count >= 20,
            header.starts(with: sqliteMagic),
            header[18] == 2 || header[19] == 2
        {
            throw LegacyDatabaseRequiresRecovery()
        }
    }

    private static func removeDatabaseFiles(at url: URL, fileManager: FileManager) {
        for suffix in ["", "-journal", "-shm", "-wal"] {
            try? fileManager.removeItem(atPath: url.path + suffix)
        }
    }
}
