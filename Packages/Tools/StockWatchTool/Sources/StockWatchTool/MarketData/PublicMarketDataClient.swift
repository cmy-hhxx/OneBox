import Foundation

actor PublicMarketDataClient: MarketDataClient {
    private let session: URLSession
    private let redirectDelegate = RedirectRejectingDelegate()
    private let decoder = JSONDecoder()
    private let searchToken = "D43BF722C8E33DA55D5C6812C6C46"
    private let identifierStore: EastMoneyIdentifierStore
    private var eastMoneyIdentifiers: [InstrumentID: String] = [:]

    init(
        session: URLSession? = nil,
        identifierStore: EastMoneyIdentifierStore? = nil
    ) {
        self.identifierStore =
            identifierStore
            ?? EastMoneyIdentifierStore(defaults: session == nil ? .standard : nil)
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 15
            configuration.timeoutIntervalForResource = 20
            configuration.waitsForConnectivity = false
            self.session = URLSession(configuration: configuration)
        }
    }

    func searchInstruments(matching query: String) async throws -> [Instrument] {
        let cleanQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanQuery.isEmpty else { return [] }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "searchapi.eastmoney.com"
        components.path = "/api/suggest/get"
        components.queryItems = [
            URLQueryItem(name: "input", value: cleanQuery),
            URLQueryItem(name: "type", value: "14"),
            URLQueryItem(name: "token", value: searchToken),
            URLQueryItem(name: "count", value: "20"),
        ]
        guard let url = components.url else { throw MarketDataError.invalidURL }

        let data = try await request(url)
        let response = try decoder.decode(EastMoneySearchEnvelope.self, from: data)
        guard response.table.status == 0 else {
            throw MarketDataError.provider(tr("搜索服务暂不可用"))
        }

        var seen = Set<InstrumentID>()
        var instruments: [Instrument] = []
        for item in response.table.data {
            guard let namespace = EastMoneyParser.namespace(for: item),
                let instrument = try? Instrument(
                    validatingSymbol: item.code,
                    name: item.name,
                    namespace: namespace
                ),
                let quoteIdentifier = EastMoneyParser.validatedQuoteIdentifier(
                    for: item,
                    instrument: instrument
                )
            else { continue }
            guard seen.insert(instrument.id).inserted else { continue }
            if instrument.namespace == .unitedStates {
                eastMoneyIdentifiers[instrument.id] = quoteIdentifier
                identifierStore.setIdentifier(quoteIdentifier, for: instrument.id)
            }
            instruments.append(instrument)
        }
        return instruments
    }

    func fetchQuote(for instrument: Instrument) async throws -> QuoteSnapshot {
        do {
            let candidate = try await fetchTencentQuote(for: instrument)
            _ = try QuoteSnapshotValidator.validatedSessionDate(
                for: candidate,
                instrument: instrument
            )
            return candidate
        } catch {
            try Task.checkCancellation()
        }

        let candidate = try await fetchEastMoneyQuote(for: instrument)
        _ = try QuoteSnapshotValidator.validatedSessionDate(
            for: candidate,
            instrument: instrument
        )
        return candidate
    }

    private func fetchTencentQuote(for instrument: Instrument) async throws -> QuoteSnapshot {
        let providerCode = TencentParser.code(for: instrument)
        var components = URLComponents()
        components.scheme = "https"
        components.host = "web.ifzq.gtimg.cn"
        components.path = "/appstock/app/minute/query"
        components.queryItems = [URLQueryItem(name: "code", value: providerCode)]
        guard let url = components.url else { throw MarketDataError.invalidURL }

        let data = try await request(url)
        let response = try decoder.decode(TencentQuoteEnvelope.self, from: data)
        guard response.code == 0,
            let payload = response.data[providerCode],
            let fields = payload.quotes[providerCode],
            fields.count > 5
        else { throw MarketDataError.invalidResponse }

        guard
            let date = TencentParser.sessionDate(
                minuteDate: payload.minute.date,
                quoteTimestamp: fields[safe: 30] ?? "",
                market: instrument.market
            )
        else { throw MarketDataError.invalidResponse }
        var bars: [MinuteBar] = []
        bars.reserveCapacity(payload.minute.values.count)
        for rawValue in payload.minute.values {
            guard
                let bar = TencentParser.minuteBar(
                    from: rawValue,
                    date: date,
                    market: instrument.market
                )
            else { throw MarketDataError.invalidResponse }
            bars.append(bar)
        }
        guard let last = bars.last else {
            throw MarketDataError.noIntradayData
        }

        let dayOpen =
            Double(fields[5]).flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
            ?? bars.first?.close
            ?? last.close
        let previousClose = Double(fields[4]) ?? .nan
        let latestPrice =
            Double(fields[3]).flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
            ?? last.close

        return QuoteSnapshot(
            instrumentID: instrument.id,
            minuteBars: bars,
            dayOpen: dayOpen,
            previousClose: previousClose,
            lastPrice: latestPrice,
            marketTime: last.time,
            receivedAt: Date(),
            source: .tencent
        )
    }

    private func fetchEastMoneyQuote(
        for instrument: Instrument
    ) async throws -> QuoteSnapshot {
        let resolution = try await eastMoneyQuoteIdentifier(for: instrument)
        do {
            return try await fetchEastMoneyQuote(
                for: instrument,
                quoteIdentifier: resolution.value
            )
        } catch {
            try Task.checkCancellation()
            guard resolution.canRefresh else { throw error }
            eastMoneyIdentifiers.removeValue(forKey: instrument.id)
            identifierStore.removeIdentifier(for: instrument.id)
            _ = try await searchInstruments(matching: instrument.symbol)
            guard let refreshedIdentifier = eastMoneyIdentifiers[instrument.id] else {
                throw error
            }
            return try await fetchEastMoneyQuote(
                for: instrument,
                quoteIdentifier: refreshedIdentifier
            )
        }
    }

    private func fetchEastMoneyQuote(
        for instrument: Instrument,
        quoteIdentifier: String
    ) async throws -> QuoteSnapshot {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "push2delay.eastmoney.com"
        components.path = "/api/qt/stock/trends2/get"
        components.queryItems = [
            URLQueryItem(name: "secid", value: quoteIdentifier),
            URLQueryItem(
                name: "fields1",
                value: "f1,f2,f3,f4,f5,f6,f7,f8,f9,f10,f11,f12,f13"
            ),
            URLQueryItem(name: "fields2", value: "f51,f52,f53,f54,f55,f56,f57,f58"),
            URLQueryItem(name: "iscr", value: "0"),
            URLQueryItem(name: "ndays", value: "1"),
        ]
        guard let url = components.url else { throw MarketDataError.invalidURL }

        let data = try await request(url)
        let response = try decoder.decode(EastMoneyTrendEnvelope.self, from: data)
        guard response.returnCode == 0, let payload = response.data else {
            throw MarketDataError.provider(tr("行情服务暂不可用"))
        }

        guard "\(payload.market).\(payload.code)" == quoteIdentifier else {
            throw MarketDataError.invalidResponse
        }

        var bars: [MinuteBar] = []
        bars.reserveCapacity(payload.trends.count)
        for rawValue in payload.trends {
            guard let bar = EastMoneyParser.minuteBar(from: rawValue) else {
                throw MarketDataError.invalidResponse
            }
            bars.append(bar)
        }
        guard let first = bars.first, let last = bars.last else {
            throw MarketDataError.noIntradayData
        }

        return QuoteSnapshot(
            instrumentID: instrument.id,
            minuteBars: bars,
            dayOpen: first.open,
            previousClose: payload.previousClose,
            lastPrice: last.close,
            marketTime: last.time,
            receivedAt: Date(),
            source: .eastMoney
        )
    }

    private func eastMoneyQuoteIdentifier(
        for instrument: Instrument
    ) async throws -> EastMoneyIdentifierResolution {
        if let deterministic = EastMoneyParser.deterministicQuoteIdentifier(for: instrument) {
            return EastMoneyIdentifierResolution(value: deterministic, canRefresh: false)
        }
        if let cached = eastMoneyIdentifiers[instrument.id] {
            return EastMoneyIdentifierResolution(value: cached, canRefresh: true)
        }
        if let persisted = identifierStore.identifier(for: instrument.id),
            Self.isValidPersistedIdentifier(persisted, for: instrument)
        {
            eastMoneyIdentifiers[instrument.id] = persisted
            return EastMoneyIdentifierResolution(value: persisted, canRefresh: true)
        }

        _ = try await searchInstruments(matching: instrument.symbol)
        guard let resolved = eastMoneyIdentifiers[instrument.id] else {
            throw MarketDataError.invalidResponse
        }
        return EastMoneyIdentifierResolution(value: resolved, canRefresh: true)
    }

    private static func isValidPersistedIdentifier(
        _ identifier: String,
        for instrument: Instrument
    ) -> Bool {
        guard instrument.namespace == .unitedStates,
            let delimiter = identifier.firstIndex(of: ".")
        else { return false }

        let marketNumber = identifier[..<delimiter]
        let symbolStart = identifier.index(after: delimiter)
        let symbol = identifier[symbolStart...]
        return ["105", "106", "107"].contains(marketNumber)
            && symbol == Substring(instrument.symbol)
    }

    private func request(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("https://quote.eastmoney.com/", forHTTPHeaderField: "Referer")

        let (data, response) = try await session.data(
            for: request,
            delegate: redirectDelegate
        )
        guard let http = response as? HTTPURLResponse,
            (200..<300).contains(http.statusCode)
        else { throw MarketDataError.invalidResponse }
        return data
    }
}

private struct EastMoneyIdentifierResolution: Sendable {
    let value: String
    let canRefresh: Bool
}

private final class RedirectRejectingDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable
{
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

extension Array {
    fileprivate subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
