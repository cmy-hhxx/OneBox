import Foundation
import XCTest

enum StockWatchPerformanceBudget {
    static let interaction: TimeInterval = 0.1

    @discardableResult
    static func recordInteraction<Result>(
        in durations: inout [TimeInterval],
        _ operation: () throws -> Result
    ) rethrows -> Result {
        let start = ProcessInfo.processInfo.systemUptime
        defer { durations.append(ProcessInfo.processInfo.systemUptime - start) }
        return try operation()
    }

    static func assertInteractionP95(
        _ durations: [TimeInterval],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertFalse(
            durations.isEmpty, "No benchmark samples were recorded", file: file, line: line)
        guard !durations.isEmpty else { return }
        let sorted = durations.sorted()
        let index = max(0, Int(ceil(Double(sorted.count) * 0.95)) - 1)
        XCTAssertLessThan(
            sorted[index],
            interaction,
            "P95 exceeded the 100 ms local interaction budget",
            file: file,
            line: line
        )
    }
}
