import Foundation
import XCTest

@testable import StockWatchTool

@MainActor
final class StockWatchModuleTests: XCTestCase {
    func testRegistrationKeepsStableIdentityAndDoesNotUsePlatformDuringRegistration() {
        let platform = RecordingStockWatchPlatformClient()

        let registration = StockWatchModule.makeRegistration(platform: platform)

        XCTAssertEqual(registration.id.rawValue, "stock-watch")
        XCTAssertEqual(registration.displayName, "股票看盘")
        XCTAssertEqual(platform.operations, [])
    }

    func testInactiveApplicationTerminationDoesNotConstructContentOrUsePlatform() async {
        let platform = RecordingStockWatchPlatformClient()
        let registration = StockWatchModule.makeRegistration(platform: platform)

        await registration.prepareForApplicationTermination()

        XCTAssertEqual(platform.operations, [])
    }

    func testApplicationTerminationHookCancelsAndWaitsForVisibleLifecycle() async throws {
        let platform = RecordingStockWatchPlatformClient()
        let session = StockWatchModuleSession()
        let registration = StockWatchModule.makeRegistration(
            platform: platform,
            session: session
        )
        let gate = VisibleLifecycleGate()
        let visibleRun = Task { @MainActor in
            await session.runVisibleLifecycle {
                await gate.run()
            }
        }
        try await gate.waitUntilStarted()
        var preparationFinished = false

        let preparation = Task { @MainActor in
            await registration.prepareForApplicationTermination()
            preparationFinished = true
        }
        try await gate.waitUntilCancelled()

        XCTAssertFalse(preparationFinished)
        await gate.finishCancellationDrain()
        await preparation.value
        await visibleRun.value
        XCTAssertTrue(preparationFinished)
        XCTAssertEqual(platform.operations, [])
    }
}

private enum VisibleLifecycleGateError: Error {
    case didNotStart
    case wasNotCancelled
}

private actor VisibleLifecycleGate {
    private var started = false
    private var cancelled = false
    private var drainContinuation: CheckedContinuation<Void, Never>?

    func run() async {
        started = true
        do {
            try await Task.sleep(for: .seconds(30))
        } catch {
            cancelled = true
            await withCheckedContinuation { continuation in
                drainContinuation = continuation
            }
        }
    }

    func waitUntilStarted() async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(1))
        while !started, clock.now < deadline {
            await Task.yield()
        }
        guard started else { throw VisibleLifecycleGateError.didNotStart }
    }

    func waitUntilCancelled() async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(1))
        while !cancelled, clock.now < deadline {
            await Task.yield()
        }
        guard cancelled else { throw VisibleLifecycleGateError.wasNotCancelled }
    }

    func finishCancellationDrain() {
        drainContinuation?.resume()
        drainContinuation = nil
    }
}

@MainActor
private final class RecordingStockWatchPlatformClient: StockWatchPlatformClient {
    enum Operation: Equatable {
        case copy(String)
        case reveal(URL)
        case play(String, String)
        case stop
    }

    private(set) var operations: [Operation] = []

    func copyText(_ text: String) -> Bool {
        operations.append(.copy(text))
        return true
    }

    func revealDirectory(_ directory: URL) -> Bool {
        operations.append(.reveal(directory))
        return true
    }

    func playAlertSound(named resourceName: String, fileExtension: String) -> Bool {
        operations.append(.play(resourceName, fileExtension))
        return true
    }

    func stopAlertSound() {
        operations.append(.stop)
    }
}
