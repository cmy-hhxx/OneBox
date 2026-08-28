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
