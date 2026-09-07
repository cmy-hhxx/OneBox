import Foundation
import OneBoxRuntime

@MainActor
public enum StockWatchModule {
    private static let id = ToolID(rawValue: "stock-watch")

    public static func makeRegistration(
        platform: any StockWatchPlatformClient,
        applicationSupportDirectoryURL: URL? = nil,
        preferences: UserDefaults? = nil,
        allowsNetworkAccess: Bool = true
    ) -> ToolRegistration {
        makeRegistration(
            platform: platform,
            session: StockWatchModuleSession(
                applicationSupportDirectoryURL: applicationSupportDirectoryURL,
                preferences: preferences,
                allowsNetworkAccess: allowsNetworkAccess
            )
        )
    }

    static func makeRegistration(
        platform: any StockWatchPlatformClient,
        session: StockWatchModuleSession
    ) -> ToolRegistration {
        ToolRegistration(
            id: id,
            displayName: "股票看盘",
            onApplicationTermination: {
                await session.prepareForApplicationTermination()
            },
            content: {
                StockWatchView(
                    platform: platform,
                    lifecycleCoordinator: session.lifecycleCoordinator,
                    session: session
                )
            }
        )
    }
}

@MainActor
final class StockWatchModuleSession {
    let lifecycleCoordinator = StockWatchLifecycleCoordinator()
    private let applicationSupportDirectoryURL: URL?
    private let preferences: UserDefaults?
    private let allowsNetworkAccess: Bool

    private var visibleRuns: [UUID: Task<Void, Never>] = [:]
    private var isPreparingForApplicationTermination = false

    init(
        applicationSupportDirectoryURL: URL? = nil,
        preferences: UserDefaults? = nil,
        allowsNetworkAccess: Bool = true
    ) {
        self.applicationSupportDirectoryURL = applicationSupportDirectoryURL
        self.preferences = preferences
        self.allowsNetworkAccess = allowsNetworkAccess
    }

    func makeBootstrap(
        platform: any StockWatchPlatformClient
    ) -> StockWatchBootstrap {
        let storage: StockWatchStorage
        if let applicationSupportDirectoryURL {
            storage = StockWatchStorage(
                applicationSupportDirectory: applicationSupportDirectoryURL
            )
        } else {
            storage = StockWatchStorage()
        }
        let client: any MarketDataClient =
            allowsNetworkAccess ? PublicMarketDataClient() : OfflineMarketDataClient()

        return StockWatchBootstrap(
            platform: platform,
            lifecycleCoordinator: lifecycleCoordinator,
            preferencesFactory: { [preferences] in
                guard let preferences else { return StockWatchPreferences() }
                return StockWatchPreferences(
                    defaults: preferences,
                    legacyDefaults: nil
                )
            },
            client: client,
            storage: storage
        )
    }

    func runVisibleLifecycle(
        _ operation: @escaping @MainActor () async -> Void
    ) async {
        guard !isPreparingForApplicationTermination else { return }

        let id = UUID()
        let task = Task { @MainActor in
            await operation()
        }
        visibleRuns[id] = task
        await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
        visibleRuns[id] = nil
    }

    func prepareForApplicationTermination() async {
        isPreparingForApplicationTermination = true
        let runs = visibleRuns
        for task in runs.values {
            task.cancel()
        }
        for task in runs.values {
            await task.value
        }
        for id in runs.keys {
            visibleRuns[id] = nil
        }
    }
}

private struct OfflineMarketDataClient: MarketDataClient {
    func searchInstruments(matching query: String) async throws -> [Instrument] {
        []
    }

    func fetchQuote(for instrument: Instrument) async throws -> QuoteSnapshot {
        throw URLError(.notConnectedToInternet)
    }
}
