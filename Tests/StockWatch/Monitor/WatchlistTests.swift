import XCTest

@testable import StockWatchTool

final class WatchlistTests: XCTestCase {
    func testDuplicateInstrumentIdentitiesAreCollapsedWithoutChangingOrder() {
        let first = Instrument(symbol: "aapl", name: "苹果", namespace: .unitedStates)
        let duplicate = Instrument(symbol: "AAPL", name: "Apple", namespace: .unitedStates)
        let second = Instrument(symbol: "00700", name: "腾讯控股", namespace: .hongKong)

        let watchlist = Watchlist([first, duplicate, second])

        XCTAssertEqual(watchlist.instruments, [first, second])
    }

    func testMovingMultipleInstrumentsPreservesTheirRelativeOrder() {
        let instruments = (0..<5).map {
            Instrument(symbol: "TEST\($0)", name: "测试\($0)", namespace: .unitedStates)
        }
        var watchlist = Watchlist(instruments)

        watchlist.move(from: IndexSet([1, 2]), to: 5)

        XCTAssertEqual(
            watchlist.instruments.map(\.symbol),
            ["TEST0", "TEST3", "TEST4", "TEST1", "TEST2"]
        )
    }
}
