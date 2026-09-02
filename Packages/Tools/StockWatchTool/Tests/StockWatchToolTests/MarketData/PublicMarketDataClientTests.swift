import XCTest
import os

@testable import StockWatchTool

final class PublicMarketDataClientTests: XCTestCase {
    override func tearDown() {
        StubURLProtocol.handler = nil
        StubURLProtocol.redirectHandler = nil
        super.tearDown()
    }

    func testSearchReturnsDeduplicatedProviderIndependentInstruments() async throws {
        StubURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.host, "searchapi.eastmoney.com")
            return Self.response(
                for: request,
                json: """
                    {
                      "QuotationCodeTable": {
                        "Data": [
                          {"Code":"AAPL","Name":"苹果","Classify":"UsStock","SecurityType":"20","MktNum":"105","QuoteID":"105.AAPL"},
                          {"Code":"AAPL","Name":"苹果","Classify":"UsStock","SecurityType":"20","MktNum":"105","QuoteID":"105.AAPL"}
                        ],
                        "Status": 0,
                        "Message": "OK"
                      }
                    }
                    """
            )
        }
        let client = PublicMarketDataClient(session: makeSession())

        let instruments = try await client.searchInstruments(matching: " AAPL ")

        XCTAssertEqual(
            instruments,
            [Instrument(symbol: "AAPL", name: "苹果", namespace: .unitedStates)]
        )
    }

    func testSearchTreatsSuccessfulNullDataAsEmpty() async throws {
        StubURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.host, "searchapi.eastmoney.com")
            return Self.response(
                for: request,
                json: """
                    {
                      "QuotationCodeTable": {
                        "Data": null,
                        "Status": 0,
                        "Message": "成功",
                        "TotalCount": 0,
                        "BizCode": "",
                        "BizMsg": ""
                      }
                    }
                    """
            )
        }
        let client = PublicMarketDataClient(session: makeSession())

        let instruments = try await client.searchInstruments(matching: "不存在的标的")

        XCTAssertTrue(instruments.isEmpty)
    }

    func testInjectedSessionRejectsRedirectBeforeRequestingSecondHost() async throws {
        let requestedHosts = OSAllocatedUnfairLock<[String]>(initialState: [])
        StubURLProtocol.redirectHandler = { request in
            let host = request.url?.host ?? "nil"
            requestedHosts.withLock { $0.append(host) }
            guard host == "searchapi.eastmoney.com" else { return nil }

            let redirectedRequest = URLRequest(
                url: URL(string: "https://redirect.invalid/collect")!
            )
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 302,
                httpVersion: nil,
                headerFields: ["Location": redirectedRequest.url!.absoluteString]
            )!
            return (redirectedRequest, response)
        }
        StubURLProtocol.handler = { request in
            XCTFail("Redirect reached second host: \(request.url?.host ?? "nil")")
            return Self.response(for: request, json: "{}", statusCode: 500)
        }
        let client = PublicMarketDataClient(
            session: makeSession(timeoutIntervalForRequest: 0.25)
        )

        do {
            _ = try await client.searchInstruments(matching: "AAPL")
            XCTFail("Expected redirect to fail")
        } catch {
            // Expected.
        }

        XCTAssertEqual(requestedHosts.withLock { $0 }, ["searchapi.eastmoney.com"])
    }

    func testSearchKeepsSameSymbolFromDifferentAShareNamespaces() async throws {
        StubURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.host, "searchapi.eastmoney.com")
            return Self.response(
                for: request,
                json: """
                    {
                      "QuotationCodeTable": {
                        "Data": [
                          {"Code":"000001","Name":"平安银行","Classify":"AStock","SecurityType":"2","MktNum":"0","QuoteID":"0.000001"},
                          {"Code":"000001","Name":"上证指数","Classify":"Index","SecurityType":"5","MktNum":"1","QuoteID":"1.000001"}
                        ],
                        "Status": 0,
                        "Message": "OK"
                      }
                    }
                    """
            )
        }
        let client = PublicMarketDataClient(session: makeSession())

        let instruments = try await client.searchInstruments(matching: "000001")

        XCTAssertEqual(
            instruments,
            [
                Instrument(symbol: "000001", name: "平安银行", namespace: .shenzhen),
                Instrument(symbol: "000001", name: "上证指数", namespace: .shanghai),
            ]
        )
    }

    func testQuoteFallsBackToEastMoneyWhenTencentFails() async throws {
        StubURLProtocol.handler = { request in
            if request.url?.host == "web.ifzq.gtimg.cn" {
                return Self.response(for: request, json: "{}", statusCode: 503)
            }
            if request.url?.host == "searchapi.eastmoney.com" {
                return Self.response(
                    for: request,
                    json: """
                        {
                          "QuotationCodeTable": {
                            "Data": [
                              {"Code":"AAPL","Name":"苹果","Classify":"UsStock","SecurityType":"20","MktNum":"105","QuoteID":"105.AAPL"}
                            ],
                            "Status": 0,
                            "Message": "OK"
                          }
                        }
                        """
                )
            }
            XCTAssertEqual(request.url?.host, "push2delay.eastmoney.com")
            return Self.response(
                for: request,
                json: """
                    {
                      "rc": 0,
                      "data": {
                        "code": "AAPL",
                        "market": 105,
                        "preClose": 208.50,
                        "trends": [
                          "2026-07-30 21:30,209.00,209.20,209.30,208.90,1,1,1",
                          "2026-07-30 21:31,209.20,210.00,210.10,209.10,1,1,1"
                        ]
                      }
                    }
                    """
            )
        }
        let client = PublicMarketDataClient(session: makeSession())
        let instrument = Instrument.initialWatchlist[2]

        let quote = try await client.fetchQuote(for: instrument)

        XCTAssertEqual(quote.instrumentID, instrument.id)
        XCTAssertEqual(quote.source, .eastMoney)
        XCTAssertEqual(quote.minuteBars.count, 2)
        XCTAssertEqual(quote.lastPrice, 210, accuracy: 0.001)
        XCTAssertEqual(quote.previousClose, 208.5, accuracy: 0.001)
        XCTAssertEqual(
            quote.marketTime,
            ISO8601DateFormatter().date(from: "2026-07-30T13:31:00Z")
        )
    }

    func testUSQuoteIdentifierPersistsAcrossClientSessions() async throws {
        let suiteName = "PublicMarketDataIdentifierTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let requestedHosts = OSAllocatedUnfairLock<[String]>(initialState: [])
        StubURLProtocol.handler = { request in
            let host = request.url?.host ?? "nil"
            requestedHosts.withLock { $0.append(host) }
            switch host {
            case "searchapi.eastmoney.com":
                return Self.response(
                    for: request,
                    json: """
                        {
                          "QuotationCodeTable": {
                            "Data": [
                              {"Code":"AAPL","Name":"苹果","Classify":"UsStock","SecurityType":"20","MktNum":"105","QuoteID":"105.AAPL"}
                            ],
                            "Status": 0,
                            "Message": "OK"
                          }
                        }
                        """
                )
            case "web.ifzq.gtimg.cn":
                return Self.response(for: request, json: "{}", statusCode: 503)
            case "push2delay.eastmoney.com":
                return Self.response(
                    for: request,
                    json: """
                        {
                          "rc": 0,
                          "data": {
                            "code": "AAPL",
                            "market": 105,
                            "preClose": 208.50,
                            "trends": [
                              "2026-07-30 21:30,209.00,209.20,209.30,208.90,1,1,1",
                              "2026-07-30 21:31,209.20,210.00,210.10,209.10,1,1,1"
                            ]
                          }
                        }
                        """
                )
            default:
                XCTFail("Unexpected host: \(host)")
                return Self.response(for: request, json: "{}", statusCode: 500)
            }
        }
        let instrument = Instrument.initialWatchlist[2]
        let searchClient = PublicMarketDataClient(
            session: makeSession(),
            identifierStore: EastMoneyIdentifierStore(defaults: defaults)
        )

        _ = try await searchClient.searchInstruments(matching: instrument.symbol)

        let restoredClient = PublicMarketDataClient(
            session: makeSession(),
            identifierStore: EastMoneyIdentifierStore(defaults: defaults)
        )
        let quote = try await restoredClient.fetchQuote(for: instrument)
        let hosts = requestedHosts.withLock { $0 }

        XCTAssertEqual(quote.source, .eastMoney)
        XCTAssertEqual(hosts.filter { $0 == "searchapi.eastmoney.com" }.count, 1)
        XCTAssertEqual(hosts.last, "push2delay.eastmoney.com")
    }

    func testStalePersistedUSIdentifierIsResolvedAgainAndReplaced() async throws {
        let requestedIdentifiers = OSAllocatedUnfairLock<[String]>(initialState: [])
        let identifierStore = EastMoneyIdentifierStore(defaults: nil)
        let instrument = Instrument.initialWatchlist[2]
        identifierStore.setIdentifier("105.\(instrument.symbol)", for: instrument.id)
        StubURLProtocol.handler = { request in
            switch request.url?.host {
            case "web.ifzq.gtimg.cn":
                return Self.response(for: request, json: "{}", statusCode: 503)
            case "searchapi.eastmoney.com":
                return Self.response(
                    for: request,
                    json: """
                        {
                          "QuotationCodeTable": {
                            "Data": [
                              {"Code":"AAPL","Name":"苹果","Classify":"UsStock","SecurityType":"20","MktNum":"106","QuoteID":"106.AAPL"}
                            ],
                            "Status": 0,
                            "Message": "OK"
                          }
                        }
                        """
                )
            case "push2delay.eastmoney.com":
                let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)
                let identifier =
                    components?.queryItems?.first(where: { $0.name == "secid" })?.value
                    ?? ""
                requestedIdentifiers.withLock { $0.append(identifier) }
                guard identifier == "106.AAPL" else {
                    return Self.response(for: request, json: #"{"rc":-1,"data":null}"#)
                }
                return Self.response(
                    for: request,
                    json: """
                        {
                          "rc": 0,
                          "data": {
                            "code": "AAPL",
                            "market": 106,
                            "preClose": 208.50,
                            "trends": [
                              "2026-07-30 21:30,209.00,209.20,209.30,208.90,1,1,1",
                              "2026-07-30 21:31,209.20,210.00,210.10,209.10,1,1,1"
                            ]
                          }
                        }
                        """
                )
            default:
                XCTFail("Unexpected host: \(request.url?.host ?? "nil")")
                return Self.response(for: request, json: "{}", statusCode: 500)
            }
        }
        let client = PublicMarketDataClient(
            session: makeSession(),
            identifierStore: identifierStore
        )

        let quote = try await client.fetchQuote(for: instrument)

        XCTAssertEqual(quote.source, .eastMoney)
        XCTAssertEqual(requestedIdentifiers.withLock { $0 }, ["105.AAPL", "106.AAPL"])
        XCTAssertEqual(identifierStore.identifier(for: instrument.id), "106.AAPL")
    }

    func testInvalidTencentCandidateFallsBackToValidEastMoney() async throws {
        StubURLProtocol.handler = { request in
            switch request.url?.host {
            case "web.ifzq.gtimg.cn":
                return Self.response(
                    for: request,
                    json: """
                        {
                          "code": 0,
                          "data": {
                            "sh600519": {
                              "data": {
                                "data": [
                                  "0931 1501.00 1 1",
                                  "0930 1500.00 1 1"
                                ],
                                "date": "20260806"
                              },
                              "qt": {
                                "sh600519": ["", "", "", "1501.00", "1490.00", "1495.00"]
                              }
                            }
                          }
                        }
                        """
                )
            case "push2delay.eastmoney.com":
                return Self.response(
                    for: request,
                    json: """
                        {
                          "rc": 0,
                          "data": {
                            "code": "600519",
                            "market": 1,
                            "preClose": 1490.00,
                            "trends": [
                              "2026-08-06 09:30,1495.00,1500.00,1501.00,1494.00,1,1,1",
                              "2026-08-06 09:31,1500.00,1502.00,1503.00,1499.00,1,1,1"
                            ]
                          }
                        }
                        """
                )
            default:
                XCTFail("Unexpected host: \(request.url?.host ?? "nil")")
                return Self.response(for: request, json: "{}", statusCode: 500)
            }
        }
        let client = PublicMarketDataClient(session: makeSession())
        let instrument = Instrument.initialWatchlist[0]

        let quote = try await client.fetchQuote(for: instrument)

        XCTAssertEqual(quote.source, .eastMoney)
        XCTAssertEqual(quote.lastPrice, 1_502, accuracy: 0.001)
    }

    func testInvalidEastMoneyCandidateFails() async throws {
        StubURLProtocol.handler = { request in
            switch request.url?.host {
            case "web.ifzq.gtimg.cn":
                return Self.response(for: request, json: "{}", statusCode: 503)
            case "push2delay.eastmoney.com":
                return Self.response(
                    for: request,
                    json: """
                        {
                          "rc": 0,
                          "data": {
                            "code": "600519",
                            "market": 1,
                            "preClose": 1490.00,
                            "trends": [
                              "2026-08-06 09:31,1500.00,1502.00,1503.00,1499.00,1,1,1",
                              "2026-08-06 09:30,1495.00,1500.00,1501.00,1494.00,1,1,1"
                            ]
                          }
                        }
                        """
                )
            default:
                XCTFail("Unexpected host: \(request.url?.host ?? "nil")")
                return Self.response(for: request, json: "{}", statusCode: 500)
            }
        }
        let client = PublicMarketDataClient(session: makeSession())

        do {
            _ = try await client.fetchQuote(for: Instrument.initialWatchlist[0])
            XCTFail("Expected invalid EastMoney candidate to fail")
        } catch QuoteSnapshotValidationError.minuteTimesNotStrictlyIncreasing {
            // Expected.
        }
    }

    func testProviderOHLCInconsistencyStillProducesPersistableSnapshot() async throws {
        StubURLProtocol.handler = { request in
            switch request.url?.host {
            case "web.ifzq.gtimg.cn":
                return Self.response(for: request, json: "{}", statusCode: 503)
            case "searchapi.eastmoney.com":
                return Self.response(
                    for: request,
                    json: """
                        {
                          "QuotationCodeTable": {
                            "Data": [
                              {"Code":"AAPL","Name":"苹果","Classify":"UsStock","SecurityType":"20","MktNum":"105","QuoteID":"105.AAPL"}
                            ],
                            "Status": 0,
                            "Message": "OK"
                          }
                        }
                        """
                )
            case "push2delay.eastmoney.com":
                return Self.response(
                    for: request,
                    json: """
                        {
                          "rc": 0,
                          "data": {
                            "code": "AAPL",
                            "market": 105,
                            "preClose": 306.90,
                            "trends": [
                              "2026-08-11 03:59,307.850,307.855,307.870,307.670,377815,116307446.000,307.1253",
                              "2026-08-11 04:00,307.855,308.260,308.250,307.800,10600910,3259890016.000,306.8981"
                            ]
                          }
                        }
                        """
                )
            default:
                XCTFail("Unexpected host: \(request.url?.host ?? "nil")")
                return Self.response(for: request, json: "{}", statusCode: 500)
            }
        }
        let client = PublicMarketDataClient(session: makeSession())
        let instrument = Instrument.initialWatchlist[2]
        let database = try MarketDatabase.inMemory()
        try await database.replaceWatchlist(with: [instrument])

        let quote = try await client.fetchQuote(for: instrument)
        let saved = try await database.saveQuote(quote, for: instrument)
        let lastBar = try XCTUnwrap(quote.minuteBars.last)

        XCTAssertTrue(saved)
        XCTAssertEqual(lastBar.close, 308.260, accuracy: 0.001)
        XCTAssertEqual(lastBar.high, 308.260, accuracy: 0.001)
    }

    func testUSFallbackResolvesItsProviderIdentifierWithoutPriorSearch() async throws {
        StubURLProtocol.handler = { request in
            switch request.url?.host {
            case "web.ifzq.gtimg.cn":
                return Self.response(for: request, json: "{}", statusCode: 503)
            case "searchapi.eastmoney.com":
                return Self.response(
                    for: request,
                    json: """
                        {
                          "QuotationCodeTable": {
                            "Data": [
                              {"Code":"MSFT","Name":"微软","Classify":"UsStock","SecurityType":"20","MktNum":"106","QuoteID":"106.MSFT"}
                            ],
                            "Status": 0,
                            "Message": "OK"
                          }
                        }
                        """
                )
            case "push2delay.eastmoney.com":
                let components = URLComponents(
                    url: request.url!,
                    resolvingAgainstBaseURL: false
                )
                XCTAssertEqual(
                    components?.queryItems?.first(where: { $0.name == "secid" })?.value,
                    "106.MSFT"
                )
                return Self.response(
                    for: request,
                    json: """
                        {
                          "rc": 0,
                          "data": {
                            "code": "MSFT",
                            "market": 106,
                            "preClose": 500.00,
                            "trends": [
                              "2026-07-30 21:30,501.00,501.20,501.30,500.90,1,1,1",
                              "2026-07-30 21:31,501.20,502.00,502.10,501.10,1,1,1"
                            ]
                          }
                        }
                        """
                )
            default:
                XCTFail("Unexpected host: \(request.url?.host ?? "nil")")
                return Self.response(for: request, json: "{}", statusCode: 500)
            }
        }
        let client = PublicMarketDataClient(session: makeSession())
        let instrument = Instrument(symbol: "MSFT", name: "微软", namespace: .unitedStates)

        let quote = try await client.fetchQuote(for: instrument)

        XCTAssertEqual(quote.instrumentID, instrument.id)
        XCTAssertEqual(quote.source, .eastMoney)
        XCTAssertEqual(quote.lastPrice, 502, accuracy: 0.001)
    }

    func testShanghaiETFFallbackUsesNamespaceWithoutPriorSearch() async throws {
        StubURLProtocol.handler = { request in
            switch request.url?.host {
            case "web.ifzq.gtimg.cn":
                let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)
                XCTAssertEqual(
                    components?.queryItems?.first(where: { $0.name == "code" })?.value,
                    "sh510300"
                )
                return Self.response(for: request, json: "{}", statusCode: 503)
            case "push2delay.eastmoney.com":
                let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)
                XCTAssertEqual(
                    components?.queryItems?.first(where: { $0.name == "secid" })?.value,
                    "1.510300"
                )
                return Self.response(
                    for: request,
                    json: """
                        {
                          "rc": 0,
                          "data": {
                            "code": "510300",
                            "market": 1,
                            "preClose": 4.20,
                            "trends": [
                              "2026-07-30 09:30,4.21,4.22,4.23,4.20,1,1,1",
                              "2026-07-30 09:31,4.22,4.24,4.25,4.21,1,1,1"
                            ]
                          }
                        }
                        """
                )
            default:
                XCTFail("Unexpected host: \(request.url?.host ?? "nil")")
                return Self.response(for: request, json: "{}", statusCode: 500)
            }
        }
        let client = PublicMarketDataClient(session: makeSession())
        let instrument = Instrument(
            symbol: "510300",
            name: "沪深300ETF华泰柏瑞",
            namespace: .shanghai
        )

        let quote = try await client.fetchQuote(for: instrument)

        XCTAssertEqual(quote.instrumentID, instrument.id)
        XCTAssertEqual(quote.source, .eastMoney)
        XCTAssertEqual(quote.lastPrice, 4.24, accuracy: 0.001)
    }

    func testBeijingSearchResultFetchesTencentBJCode() async throws {
        StubURLProtocol.handler = { request in
            switch request.url?.host {
            case "searchapi.eastmoney.com":
                return Self.response(
                    for: request,
                    json: """
                        {
                          "QuotationCodeTable": {
                            "Data": [
                              {"Code":"920001","Name":"纬达光电","Classify":"NEEQ","SecurityType":"27","MktNum":"0","QuoteID":"0.920001"},
                              {"Code":"899001","Name":"三板成指","Classify":"NEEQ","SecurityType":"10","MktNum":"0","QuoteID":"0.899001"}
                            ],
                            "Status": 0,
                            "Message": "OK"
                          }
                        }
                        """
                )
            case "web.ifzq.gtimg.cn":
                let components = URLComponents(
                    url: request.url!,
                    resolvingAgainstBaseURL: false
                )
                XCTAssertEqual(
                    components?.queryItems?.first(where: { $0.name == "code" })?.value,
                    "bj920001"
                )
                return Self.response(
                    for: request,
                    json: """
                        {
                          "code": 0,
                          "data": {
                            "bj920001": {
                              "data": {
                                "data": [
                                  "0930 10.00 1 1",
                                  "0931 10.10 1 1"
                                ],
                                "date": "20260806"
                              },
                              "qt": {
                                "bj920001": ["", "", "", "10.10", "9.90", "10.00"]
                              }
                            }
                          }
                        }
                        """
                )
            default:
                XCTFail("Unexpected host: \(request.url?.host ?? "nil")")
                return Self.response(for: request, json: "{}", statusCode: 500)
            }
        }
        let client = PublicMarketDataClient(session: makeSession())

        let searchResults = try await client.searchInstruments(matching: "920001")
        let instrument = try XCTUnwrap(searchResults.first)
        let quote = try await client.fetchQuote(for: instrument)

        XCTAssertEqual(searchResults.count, 1)
        XCTAssertEqual(instrument.namespace, .beijing)
        XCTAssertEqual(quote.instrumentID, instrument.id)
        XCTAssertEqual(quote.source, .tencent)
        XCTAssertEqual(quote.lastPrice, 10.10, accuracy: 0.001)
    }

    func testMismatchedEastMoneyIdentifierIsRejectedBeforeFallbackRequest() async throws {
        StubURLProtocol.handler = { request in
            switch request.url?.host {
            case "web.ifzq.gtimg.cn":
                return Self.response(for: request, json: "{}", statusCode: 503)
            case "searchapi.eastmoney.com":
                return Self.response(
                    for: request,
                    json: """
                        {
                          "QuotationCodeTable": {
                            "Data": [
                              {"Code":"AAPL","Name":"苹果","Classify":"UsStock","SecurityType":"20","MktNum":"105","QuoteID":"105.MSFT"}
                            ],
                            "Status": 0,
                            "Message": "OK"
                          }
                        }
                        """
                )
            case "push2delay.eastmoney.com":
                XCTFail("A mismatched identifier must not reach the trends endpoint")
                return Self.response(for: request, json: "{}", statusCode: 500)
            default:
                XCTFail("Unexpected host: \(request.url?.host ?? "nil")")
                return Self.response(for: request, json: "{}", statusCode: 500)
            }
        }
        let client = PublicMarketDataClient(session: makeSession())

        let searchResults = try await client.searchInstruments(matching: "AAPL")
        XCTAssertTrue(searchResults.isEmpty)

        do {
            _ = try await client.fetchQuote(for: Instrument.initialWatchlist[2])
            XCTFail("Expected invalid identifier resolution to fail")
        } catch MarketDataError.invalidResponse {
            // Expected.
        }
    }

    func testTencentAcceptsSingleValidMinuteBar() async throws {
        StubURLProtocol.handler = { request in
            guard request.url?.host == "web.ifzq.gtimg.cn" else {
                XCTFail("A valid Tencent quote must not fall back")
                return Self.response(for: request, json: "{}", statusCode: 500)
            }
            return Self.response(
                for: request,
                json: Self.tencentQuoteJSON(
                    previousClose: "1490.00",
                    minuteValues: ["0930 1500.00 1 1"]
                )
            )
        }
        let client = PublicMarketDataClient(session: makeSession())

        let quote = try await client.fetchQuote(for: Instrument.initialWatchlist[0])

        XCTAssertEqual(quote.source, .tencent)
        XCTAssertEqual(quote.minuteBars.count, 1)
    }

    func testEastMoneyAcceptsSingleValidMinuteBar() async throws {
        StubURLProtocol.handler = { request in
            switch request.url?.host {
            case "web.ifzq.gtimg.cn":
                return Self.response(for: request, json: "{}", statusCode: 503)
            case "push2delay.eastmoney.com":
                return Self.response(
                    for: request,
                    json: Self.eastMoneyQuoteJSON(
                        previousClose: "1490.00",
                        trends: [
                            "2026-08-06 09:30,1495.00,1500.00,1501.00,1494.00,1,1,1"
                        ]
                    )
                )
            default:
                XCTFail("Unexpected host: \(request.url?.host ?? "nil")")
                return Self.response(for: request, json: "{}", statusCode: 500)
            }
        }
        let client = PublicMarketDataClient(session: makeSession())

        let quote = try await client.fetchQuote(for: Instrument.initialWatchlist[0])

        XCTAssertEqual(quote.source, .eastMoney)
        XCTAssertEqual(quote.minuteBars.count, 1)
    }

    func testMismatchedEastMoneyTrendIdentityIsRejected() async throws {
        StubURLProtocol.handler = { request in
            switch request.url?.host {
            case "web.ifzq.gtimg.cn":
                return Self.response(for: request, json: "{}", statusCode: 503)
            case "push2delay.eastmoney.com":
                return Self.response(
                    for: request,
                    json: Self.eastMoneyQuoteJSON(
                        previousClose: "1490.00",
                        code: "000001",
                        market: 1
                    )
                )
            default:
                XCTFail("Unexpected host: \(request.url?.host ?? "nil")")
                return Self.response(for: request, json: "{}", statusCode: 500)
            }
        }
        let client = PublicMarketDataClient(session: makeSession())

        do {
            _ = try await client.fetchQuote(for: Instrument.initialWatchlist[0])
            XCTFail("Expected mismatched trend identity to fail")
        } catch MarketDataError.invalidResponse {
            // Expected.
        }
    }

    func testInvalidTencentPreviousCloseFallsBackToEastMoney() async throws {
        for previousClose in ["0", "Infinity"] {
            StubURLProtocol.handler = { request in
                switch request.url?.host {
                case "web.ifzq.gtimg.cn":
                    return Self.response(
                        for: request,
                        json: Self.tencentQuoteJSON(previousClose: previousClose)
                    )
                case "push2delay.eastmoney.com":
                    return Self.response(
                        for: request,
                        json: Self.eastMoneyQuoteJSON(previousClose: "1490.00")
                    )
                default:
                    XCTFail("Unexpected host: \(request.url?.host ?? "nil")")
                    return Self.response(for: request, json: "{}", statusCode: 500)
                }
            }
            let client = PublicMarketDataClient(session: makeSession())

            let quote = try await client.fetchQuote(for: Instrument.initialWatchlist[0])

            XCTAssertEqual(quote.source, .eastMoney, "previousClose=\(previousClose)")
            XCTAssertEqual(quote.previousClose, 1_490, accuracy: 0.001)
        }
    }

    func testInvalidEastMoneyPreviousCloseFails() async throws {
        for previousClose in ["0", "1e400"] {
            StubURLProtocol.handler = { request in
                switch request.url?.host {
                case "web.ifzq.gtimg.cn":
                    return Self.response(for: request, json: "{}", statusCode: 503)
                case "push2delay.eastmoney.com":
                    return Self.response(
                        for: request,
                        json: Self.eastMoneyQuoteJSON(previousClose: previousClose)
                    )
                default:
                    XCTFail("Unexpected host: \(request.url?.host ?? "nil")")
                    return Self.response(for: request, json: "{}", statusCode: 500)
                }
            }
            let client = PublicMarketDataClient(session: makeSession())

            do {
                _ = try await client.fetchQuote(for: Instrument.initialWatchlist[0])
                XCTFail("Expected previousClose=\(previousClose) to fail")
            } catch {
                // Expected.
            }
        }
    }

    func testMissingOrMalformedTencentSessionDateFallsBack() async throws {
        let invalidDates = [
            (minuteDate: "", quoteTimestamp: ""),
            (minuteDate: "2026oops0806", quoteTimestamp: "2026-08-06garbage"),
        ]
        for invalidDate in invalidDates {
            StubURLProtocol.handler = { request in
                switch request.url?.host {
                case "web.ifzq.gtimg.cn":
                    return Self.response(
                        for: request,
                        json: Self.tencentQuoteJSON(
                            previousClose: "1490.00",
                            minuteDate: invalidDate.minuteDate,
                            quoteTimestamp: invalidDate.quoteTimestamp
                        )
                    )
                case "push2delay.eastmoney.com":
                    return Self.response(
                        for: request,
                        json: Self.eastMoneyQuoteJSON(previousClose: "1490.00")
                    )
                default:
                    XCTFail("Unexpected host: \(request.url?.host ?? "nil")")
                    return Self.response(for: request, json: "{}", statusCode: 500)
                }
            }
            let client = PublicMarketDataClient(session: makeSession())

            let quote = try await client.fetchQuote(for: Instrument.initialWatchlist[0])

            XCTAssertEqual(quote.source, .eastMoney)
        }
    }

    func testTencentUsesDocumentedQuoteTimestampWhenMinuteDateIsAbsent() async throws {
        StubURLProtocol.handler = { request in
            switch request.url?.host {
            case "web.ifzq.gtimg.cn":
                return Self.response(
                    for: request,
                    json: Self.tencentQuoteJSON(
                        previousClose: "1490.00",
                        minuteDate: "",
                        quoteTimestamp: "20260806150000"
                    )
                )
            case "push2delay.eastmoney.com":
                XCTFail("A valid Tencent timestamp must not fall back")
                return Self.response(for: request, json: "{}", statusCode: 500)
            default:
                XCTFail("Unexpected host: \(request.url?.host ?? "nil")")
                return Self.response(for: request, json: "{}", statusCode: 500)
            }
        }
        let client = PublicMarketDataClient(session: makeSession())

        let quote = try await client.fetchQuote(for: Instrument.initialWatchlist[0])

        XCTAssertEqual(quote.source, .tencent)
        XCTAssertEqual(
            TradingCalendar.sessionDate(for: quote.marketTime, market: .aShare),
            "2026-08-06"
        )
    }

    private func makeSession(
        timeoutIntervalForRequest: TimeInterval = 60
    ) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeoutIntervalForRequest
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private static func tencentQuoteJSON(
        previousClose: String,
        minuteDate: String = "20260806",
        quoteTimestamp: String = "",
        minuteValues: [String] = [
            "0930 1500.00 1 1",
            "0931 1502.00 1 1",
        ]
    ) -> String {
        var fields = Array(repeating: "", count: 31)
        fields[3] = "1502.00"
        fields[4] = previousClose
        fields[5] = "1495.00"
        fields[30] = quoteTimestamp
        let encodedFields = fields.map { "\"\($0)\"" }.joined(separator: ",")
        let encodedMinutes = minuteValues.map { "\"\($0)\"" }.joined(separator: ",")
        return """
            {
              "code": 0,
              "data": {
                "sh600519": {
                  "data": {
                    "data": [\(encodedMinutes)],
                    "date": "\(minuteDate)"
                  },
                  "qt": {
                    "sh600519": [\(encodedFields)]
                  }
                }
              }
            }
            """
    }

    private static func eastMoneyQuoteJSON(
        previousClose: String,
        code: String = "600519",
        market: Int = 1,
        trends: [String] = [
            "2026-08-06 09:30,1495.00,1500.00,1501.00,1494.00,1,1,1",
            "2026-08-06 09:31,1500.00,1502.00,1503.00,1499.00,1,1,1",
        ]
    ) -> String {
        let encodedTrends = trends.map { "\"\($0)\"" }.joined(separator: ",")
        return """
            {
              "rc": 0,
              "data": {
                "code": "\(code)",
                "market": \(market),
                "preClose": \(previousClose),
                "trends": [\(encodedTrends)]
              }
            }
            """
    }

    private static func response(
        for request: URLRequest,
        json: String,
        statusCode: Int = 200
    ) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        return (response, Data(json.utf8))
    }
}
