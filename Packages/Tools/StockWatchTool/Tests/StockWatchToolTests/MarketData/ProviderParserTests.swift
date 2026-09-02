import XCTest

@testable import StockWatchTool

final class ProviderParserTests: XCTestCase {
    func testEastMoneyParserReadsActualTrendLayout() throws {
        let raw = "2026-07-30 09:31,1323.00,1329.50,1330.00,1322.00,753,99792267.00,1324.911"
        let bar = try XCTUnwrap(
            EastMoneyParser.minuteBar(from: raw)
        )

        XCTAssertEqual(bar.open, 1323, accuracy: 0.001)
        XCTAssertEqual(bar.close, 1329.5, accuracy: 0.001)
        XCTAssertEqual(bar.high, 1330, accuracy: 0.001)
        XCTAssertEqual(bar.low, 1322, accuracy: 0.001)
    }

    func testEastMoneyParserRejectsMalformedTimestampAndInvalidOHLC() {
        XCTAssertNil(
            EastMoneyParser.minuteBar(
                from: "2026/07/30 09:31,1323.00,1329.50,1330.00,1322.00"
            )
        )
        XCTAssertNil(
            EastMoneyParser.minuteBar(
                from: "2026-07-30 09:31 trailing,1323.00,1329.50,1330.00,1322.00"
            )
        )
        XCTAssertNil(
            EastMoneyParser.minuteBar(
                from: "2026-07-30 09:31,307.855,308.260,308.250,307.800"
            )
        )
    }

    func testEastMoneyUSMinutesUseProviderClockAndStayInOneMarketSession() throws {
        let open = try XCTUnwrap(
            EastMoneyParser.minuteBar(
                from: "2026-07-30 21:30,209.00,209.20,209.30,208.90,1,1,1"
            )
        )
        let close = try XCTUnwrap(
            EastMoneyParser.minuteBar(
                from: "2026-07-31 04:00,209.20,210.00,210.10,209.10,1,1,1"
            )
        )

        XCTAssertEqual(
            open.time,
            ISO8601DateFormatter().date(from: "2026-07-30T13:30:00Z")
        )
        XCTAssertEqual(
            close.time,
            ISO8601DateFormatter().date(from: "2026-07-30T20:00:00Z")
        )
        XCTAssertEqual(
            TradingCalendar.sessionDate(for: open.time, market: .unitedStates),
            "2026-07-30"
        )
        XCTAssertEqual(
            TradingCalendar.sessionDate(for: close.time, market: .unitedStates),
            "2026-07-30"
        )
    }

    func testTencentParserReadsActualMinuteLayoutInMarketTimeZone() throws {
        let bar = try XCTUnwrap(
            TencentParser.minuteBar(
                from: "0931 1329.50 961 127323916.11",
                date: "20260730",
                market: .aShare
            )
        )

        XCTAssertEqual(bar.close, 1329.5, accuracy: 0.001)
        XCTAssertEqual(
            TradingCalendar.sessionDate(for: bar.time, market: .aShare),
            "2026-07-30"
        )
    }

    func testTencentSessionDateRequiresExactProviderFormats() {
        XCTAssertEqual(
            TencentParser.sessionDate(
                minuteDate: "20260730",
                quoteTimestamp: "",
                market: .aShare
            ),
            "20260730"
        )
        XCTAssertEqual(
            TencentParser.sessionDate(
                minuteDate: "",
                quoteTimestamp: "20260730150000",
                market: .aShare
            ),
            "20260730"
        )
        XCTAssertEqual(
            TencentParser.sessionDate(
                minuteDate: "",
                quoteTimestamp: "2026-07-30 15:00:00",
                market: .aShare
            ),
            "20260730"
        )
        XCTAssertNil(
            TencentParser.sessionDate(
                minuteDate: "2026oops0730",
                quoteTimestamp: "2026-07-30garbage",
                market: .aShare
            )
        )
        XCTAssertNil(
            TencentParser.sessionDate(
                minuteDate: "20260230",
                quoteTimestamp: "",
                market: .aShare
            )
        )
    }

    func testEastMoneyQuoteIdentifierMustMatchTheValidatedSearchInstrument() throws {
        let dottedInstrument = Instrument(
            symbol: "BRK.B",
            name: "伯克希尔",
            namespace: .unitedStates
        )
        let validDottedItem = EastMoneySearchItem(
            code: "BRK.B",
            name: "伯克希尔",
            classification: "UsStock",
            securityType: "20",
            marketNumber: "106",
            quoteIdentifier: "106.BRK.B"
        )
        XCTAssertEqual(
            EastMoneyParser.validatedQuoteIdentifier(
                for: validDottedItem,
                instrument: dottedInstrument
            ),
            "106.BRK.B"
        )
        for marketNumber in ["105", "106", "107"] {
            let item = EastMoneySearchItem(
                code: "BRK.B",
                name: "伯克希尔",
                classification: "UsStock",
                securityType: "20",
                marketNumber: marketNumber,
                quoteIdentifier: "\(marketNumber).BRK.B"
            )
            XCTAssertEqual(
                EastMoneyParser.validatedQuoteIdentifier(
                    for: item,
                    instrument: dottedInstrument
                ),
                "\(marketNumber).BRK.B"
            )
        }

        let apple = Instrument.initialWatchlist[2]
        XCTAssertNil(
            EastMoneyParser.validatedQuoteIdentifier(
                for: EastMoneySearchItem(
                    code: "AAPL",
                    name: "苹果",
                    classification: "UsStock",
                    securityType: "20",
                    marketNumber: "105",
                    quoteIdentifier: "105.MSFT"
                ),
                instrument: apple
            )
        )
        XCTAssertNil(
            EastMoneyParser.validatedQuoteIdentifier(
                for: EastMoneySearchItem(
                    code: "AAPL",
                    name: "苹果",
                    classification: "UsStock",
                    securityType: "20",
                    marketNumber: "105",
                    quoteIdentifier: "106.AAPL"
                ),
                instrument: apple
            )
        )
        XCTAssertNil(
            EastMoneyParser.validatedQuoteIdentifier(
                for: EastMoneySearchItem(
                    code: "AAPL",
                    name: "苹果",
                    classification: "UsStock",
                    securityType: "20",
                    marketNumber: "105",
                    quoteIdentifier: "105.aapl"
                ),
                instrument: apple
            )
        )

        let shanghaiIndex = Instrument(
            symbol: "000001",
            name: "上证指数",
            namespace: .shanghai
        )
        XCTAssertNil(
            EastMoneyParser.validatedQuoteIdentifier(
                for: EastMoneySearchItem(
                    code: "000001",
                    name: "平安银行",
                    classification: "AStock",
                    securityType: "2",
                    marketNumber: "0",
                    quoteIdentifier: "0.000001"
                ),
                instrument: shanghaiIndex
            )
        )
    }

    func testProviderMappingsCoverAllSupportedMarkets() {
        XCTAssertEqual(
            TencentParser.code(for: Instrument.initialWatchlist[0]),
            "sh600519"
        )
        XCTAssertEqual(
            TencentParser.code(for: Instrument.initialWatchlist[1]),
            "hk00700"
        )
        XCTAssertEqual(
            TencentParser.code(for: Instrument.initialWatchlist[2]),
            "usAAPL"
        )

        XCTAssertEqual(
            EastMoneyParser.deterministicQuoteIdentifier(
                for: Instrument.initialWatchlist[0]
            ),
            "1.600519"
        )
        XCTAssertEqual(
            EastMoneyParser.deterministicQuoteIdentifier(
                for: Instrument.initialWatchlist[1]
            ),
            "116.00700"
        )
        XCTAssertNil(
            EastMoneyParser.deterministicQuoteIdentifier(
                for: Instrument.initialWatchlist[2]
            )
        )

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
        let beijingStock = Instrument(
            symbol: "920001",
            name: "纬达光电",
            namespace: .beijing
        )
        XCTAssertEqual(TencentParser.code(for: shanghaiIndex), "sh000001")
        XCTAssertEqual(TencentParser.code(for: shenzhenStock), "sz000001")
        XCTAssertEqual(TencentParser.code(for: beijingStock), "bj920001")
        XCTAssertEqual(
            EastMoneyParser.deterministicQuoteIdentifier(for: shanghaiIndex),
            "1.000001"
        )
        XCTAssertEqual(
            EastMoneyParser.deterministicQuoteIdentifier(for: shenzhenStock),
            "0.000001"
        )
        XCTAssertEqual(
            EastMoneyParser.deterministicQuoteIdentifier(for: beijingStock),
            "0.920001"
        )
    }

    func testEastMoneySearchItemsMapOnlyToSupportedNamespaces() {
        XCTAssertEqual(
            EastMoneyParser.namespace(
                for: EastMoneySearchItem(
                    code: "600519",
                    name: "贵州茅台",
                    classification: "AStock",
                    securityType: "2",
                    marketNumber: "1",
                    quoteIdentifier: "1.600519"
                )
            ),
            .shanghai
        )
        XCTAssertEqual(
            EastMoneyParser.namespace(
                for: EastMoneySearchItem(
                    code: "00700",
                    name: "腾讯控股",
                    classification: "HK",
                    securityType: "19",
                    marketNumber: "116",
                    quoteIdentifier: "116.00700"
                )
            ),
            .hongKong
        )
        XCTAssertEqual(
            EastMoneyParser.namespace(
                for: EastMoneySearchItem(
                    code: "AAPL",
                    name: "苹果",
                    classification: "UsStock",
                    securityType: "20",
                    marketNumber: "105",
                    quoteIdentifier: "105.AAPL"
                )
            ),
            .unitedStates
        )

        XCTAssertEqual(
            EastMoneyParser.namespace(
                for: EastMoneySearchItem(
                    code: "000001",
                    name: "平安银行",
                    classification: "AStock",
                    securityType: "2",
                    marketNumber: "0",
                    quoteIdentifier: "0.000001"
                )
            ),
            .shenzhen
        )
        XCTAssertEqual(
            EastMoneyParser.namespace(
                for: EastMoneySearchItem(
                    code: "920001",
                    name: "纬达光电",
                    classification: "NEEQ",
                    securityType: "27",
                    marketNumber: "0",
                    quoteIdentifier: "0.920001"
                )
            ),
            .beijing
        )
        for tripleBoardCode in ["400016", "899001"] {
            XCTAssertNil(
                EastMoneyParser.namespace(
                    for: EastMoneySearchItem(
                        code: tripleBoardCode,
                        name: "三板标的",
                        classification: "NEEQ",
                        securityType: "10",
                        marketNumber: "0",
                        quoteIdentifier: "0.\(tripleBoardCode)"
                    )
                )
            )
        }
        XCTAssertNil(
            EastMoneyParser.namespace(
                for: EastMoneySearchItem(
                    code: "000001",
                    name: "场外基金",
                    classification: "OTCFUND",
                    securityType: "17",
                    marketNumber: "150",
                    quoteIdentifier: "150.000001"
                )
            )
        )
    }
}
