import Foundation
import OneBoxRuntime

@MainActor
public enum StockWatchModule {
    public static let id = ToolID(rawValue: "stock-watch")

    public static func makeRegistration(
        platform: any StockWatchPlatformClient
    ) -> ToolRegistration {
        makeRegistration(
            platform: platform,
            session: StockWatchModuleSession()
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

    private var visibleRuns: [UUID: Task<Void, Never>] = [:]
    private var isPreparingForApplicationTermination = false

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
