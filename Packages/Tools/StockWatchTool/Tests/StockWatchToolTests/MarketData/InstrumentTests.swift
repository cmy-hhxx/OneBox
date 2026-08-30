import XCTest

@testable import StockWatchTool

final class InstrumentTests: XCTestCase {
    func testInstrumentIdentityIsStableAndProviderIndependent() {
        let instrument = Instrument(
            symbol: " aapl ",
            name: " Apple ",
            namespace: .unitedStates
        )

        XCTAssertEqual(instrument.id, InstrumentID(rawValue: "us:AAPL"))
        XCTAssertEqual(instrument.symbol, "AAPL")
        XCTAssertEqual(instrument.name, "Apple")
        XCTAssertEqual(instrument.market, .unitedStates)
    }

    func testSameAShareSymbolOnDifferentExchangesHasDifferentIdentity() {
        let shanghaiIndex = Instrument(
            symbol: "000001",
            name: "上证指数",
            namespace: .shanghai
        )
        let shenzhenStock = Instrument(
            symbol: "000001",
            name: "平安银行",
            namespace: .shenzhen
        )

        XCTAssertEqual(shanghaiIndex.id, InstrumentID(rawValue: "sse:000001"))
        XCTAssertEqual(shenzhenStock.id, InstrumentID(rawValue: "szse:000001"))
        XCTAssertNotEqual(shanghaiIndex.id, shenzhenStock.id)
    }

    func testInstrumentJSONDoesNotPersistProviderIdentifiers() throws {
        let instrument = Instrument(
            symbol: "600519",
            name: "贵州茅台",
            namespace: .shanghai
        )

        let data = try JSONEncoder().encode(instrument)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        XCTAssertEqual(Set(object.keys), ["name", "namespace", "symbol"])
        XCTAssertEqual(object["namespace"] as? String, "sse")
        XCTAssertEqual(try JSONDecoder().decode(Instrument.self, from: data), instrument)
    }

    func testValidatedInstrumentCanonicalizesHongKongAndUnitedStatesSymbols() throws {
        let hongKong = try Instrument(
            validatingSymbol: "700",
            name: " 腾讯控股 ",
            namespace: .hongKong
        )
        let unitedStates = try Instrument(
            validatingSymbol: " brk.b ",
            name: "Berkshire Hathaway",
            namespace: .unitedStates
        )

        XCTAssertEqual(hongKong.symbol, "00700")
        XCTAssertEqual(hongKong.id.rawValue, "hk:00700")
        XCTAssertEqual(unitedStates.symbol, "BRK.B")
    }

    func testValidatedInstrumentRejectsInvalidExternalValues() {
        XCTAssertThrowsError(
            try Instrument(validatingSymbol: "12345", name: "贵州茅台", namespace: .shanghai)
        )
        XCTAssertThrowsError(
            try Instrument(validatingSymbol: "AAPL:US", name: "Apple", namespace: .unitedStates)
        )
        XCTAssertThrowsError(
            try Instrument(
                validatingSymbol: "AAPL", name: "Bad\u{0000}Name", namespace: .unitedStates)
        )
        XCTAssertThrowsError(
            try Instrument(validatingSymbol: "AAPL", name: "   ", namespace: .unitedStates)
        )
    }

    func testJSONDecodingUsesValidatedConstruction() throws {
        let invalid = #"[{"symbol":"12345","name":"无效","namespace":"sse"}]"#
        XCTAssertThrowsError(
            try JSONDecoder().decode([Instrument].self, from: Data(invalid.utf8))
        )
    }
}
