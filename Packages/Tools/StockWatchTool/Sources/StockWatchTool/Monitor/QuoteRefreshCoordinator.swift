import Foundation
import OSLog
import OneBoxRuntime

struct QuoteRefreshBatch: Sendable {
    let outcomes: [QuoteRefreshOutcome]
}

struct QuoteRefreshOutcome: Sendable {
    let instrument: Instrument
    let result: Result

    enum Result: Sendable {
        case updated(QuoteSnapshot, storageError: String?)
        case previousSession(QuoteSnapshot, storageError: String?)
        case noData(String)
        case stale(String)
        case failed(String)
        case rejected(String)
        case discarded
    }
}

actor QuoteRefreshCoordinator {
    private static let signposter = OSSignposter(
        subsystem: "com.cmy.OneBox",
        category: "StockWatch"
    )

    private let diagnostics: ToolDiagnostics
    private let client: any MarketDataClient
    private let database: MarketDatabase
    private let maximumConcurrentRequests: Int
    private let requestLimiter: QuoteRequestLimiter
    private let now: @Sendable (Market) -> Date

    init(
        client: any MarketDataClient,
        database: MarketDatabase,
        maximumConcurrentRequests: Int = 6,
        now: @escaping @Sendable (Market) -> Date = { _ in Date() },
        diagnostics: ToolDiagnostics = .disabled
    ) {
        precondition(maximumConcurrentRequests > 0)
        self.diagnostics = diagnostics
        self.client = client
        self.database = database
        self.maximumConcurrentRequests = maximumConcurrentRequests
        self.requestLimiter = QuoteRequestLimiter(limit: maximumConcurrentRequests)
        self.now = now
    }

    func refresh(
        instruments: [Instrument],
        currentQuotes: [InstrumentID: QuoteSnapshot]
    ) async -> QuoteRefreshBatch {
        let interval = Self.signposter.beginInterval(
            "RefreshBatch",
            id: Self.signposter.makeSignpostID()
        )
        defer { Self.signposter.endInterval("RefreshBatch", interval) }

        guard !instruments.isEmpty else {
            return QuoteRefreshBatch(outcomes: [])
        }

        let diagnostics = diagnostics
        let client = client
        let database = database
        let requestLimiter = requestLimiter
        let now = now
        var indexedOutcomes: [(Int, QuoteRefreshOutcome)] = []
        await withTaskGroup(of: (Int, QuoteRefreshOutcome).self) { group in
            let initialCount = min(maximumConcurrentRequests, instruments.count)
            for index in 0..<initialCount {
                let instrument = instruments[index]
                let currentQuote = currentQuotes[instrument.id]
                group.addTask {
                    let outcome = await requestLimiter.withPermit {
                        await Self.fetch(
                            instrument: instrument,
                            currentQuote: currentQuote,
                            client: client,
                            database: database,
                            now: now,
                            diagnostics: diagnostics
                        )
                    }
                    return (
                        index,
                        outcome
                            ?? QuoteRefreshOutcome(instrument: instrument, result: .discarded)
                    )
                }
            }
            var nextIndex = initialCount

            while let outcome = await group.next() {
                indexedOutcomes.append(outcome)
                guard !Task.isCancelled else {
                    group.cancelAll()
                    break
                }
                if nextIndex < instruments.count {
                    let index = nextIndex
                    let instrument = instruments[index]
                    let currentQuote = currentQuotes[instrument.id]
                    nextIndex += 1
                    group.addTask {
                        let outcome = await requestLimiter.withPermit {
                            await Self.fetch(
                                instrument: instrument,
                                currentQuote: currentQuote,
                                client: client,
                                database: database,
                                now: now,
                                diagnostics: diagnostics
                            )
                        }
                        return (
                            index,
                            outcome
                                ?? QuoteRefreshOutcome(instrument: instrument, result: .discarded)
                        )
                    }
                }
            }
        }

        return QuoteRefreshBatch(
            outcomes:
                indexedOutcomes
                .sorted { $0.0 < $1.0 }
                .map(\.1)
        )
    }

    private static func fetch(
        instrument: Instrument,
        currentQuote: QuoteSnapshot?,
        client: any MarketDataClient,
        database: MarketDatabase,
        now: @Sendable (Market) -> Date,
        diagnostics: ToolDiagnostics
    ) async -> QuoteRefreshOutcome {
        let interval = signposter.beginInterval(
            "FetchQuote",
            id: signposter.makeSignpostID()
        )
        defer { signposter.endInterval("FetchQuote", interval) }

        do {
            try Task.checkCancellation()
            let quote = try await client.fetchQuote(for: instrument)
            try Task.checkCancellation()

            let quoteSession: String
            do {
                quoteSession = try MarketDatabase.validatedSessionDate(
                    for: quote,
                    instrument: instrument
                )
            } catch {
                diagnostics.record(error, operation: "quote.validate")
                return QuoteRefreshOutcome(
                    instrument: instrument,
                    result: .rejected(error.localizedDescription)
                )
            }
            let currentSession = TradingCalendar.sessionDate(
                for: now(instrument.market),
                market: instrument.market
            )
            guard quoteSession <= currentSession else {
                diagnostics.record(
                    message:
                        "Future quote session: source=\(quote.source.rawValue), received=\(quoteSession), expected=\(currentSession)",
                    operation: "quote.validate")
                return QuoteRefreshOutcome(
                    instrument: instrument,
                    result: .rejected(tr("行情源返回了未来交易日数据"))
                )
            }
            if let currentQuote, quote.marketTime < currentQuote.marketTime {
                diagnostics.record(
                    message:
                        "Older quote: source=\(quote.source.rawValue), received=\(quote.marketTime), cached=\(currentQuote.marketTime)",
                    operation: "quote.validate")
                return QuoteRefreshOutcome(
                    instrument: instrument,
                    result: .stale(tr("行情源返回了较旧数据"))
                )
            }
            let isCurrentSession = quoteSession == currentSession

            func persistedResult(storageError: String?) -> QuoteRefreshOutcome.Result {
                if isCurrentSession {
                    return .updated(quote, storageError: storageError)
                }
                // Public feeds retain the last session on holidays and before opening.
                // Keep its date visible without treating it as a live alert input.
                return .previousSession(quote, storageError: storageError)
            }

            do {
                let persisted = try await database.saveQuote(quote, for: instrument)
                return QuoteRefreshOutcome(
                    instrument: instrument,
                    result: persisted
                        ? persistedResult(storageError: nil)
                        : .discarded
                )
            } catch let error as MarketDatabaseError {
                try Task.checkCancellation()
                diagnostics.record(error, operation: "storage.save-quote")
                switch error {
                case .invalidQuote, .quoteInstrumentMismatch:
                    return QuoteRefreshOutcome(
                        instrument: instrument,
                        result: .rejected(error.localizedDescription)
                    )
                default:
                    return QuoteRefreshOutcome(
                        instrument: instrument,
                        result: persistedResult(storageError: error.localizedDescription)
                    )
                }
            } catch {
                try Task.checkCancellation()
                diagnostics.record(error, operation: "storage.save-quote")
                return QuoteRefreshOutcome(
                    instrument: instrument,
                    result: persistedResult(storageError: error.localizedDescription)
                )
            }
        } catch is CancellationError {
            return QuoteRefreshOutcome(instrument: instrument, result: .discarded)
        } catch MarketDataError.noIntradayData {
            diagnostics.record(MarketDataError.noIntradayData, operation: "quote.fetch")
            return QuoteRefreshOutcome(
                instrument: instrument,
                result: .noData(MarketDataError.noIntradayData.localizedDescription)
            )
        } catch {
            diagnostics.record(error, operation: "quote.fetch")
            return QuoteRefreshOutcome(
                instrument: instrument,
                result: .failed(error.localizedDescription)
            )
        }
    }
}

private actor QuoteRequestLimiter {
    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Bool, Never>
    }

    private var availablePermits: Int
    private var waiters: [Waiter] = []

    init(limit: Int) {
        availablePermits = limit
    }

    func withPermit<Result: Sendable>(
        _ operation: @Sendable () async -> Result
    ) async -> Result? {
        guard await acquire() else { return nil }
        defer { release() }
        return await operation()
    }

    private func acquire() async -> Bool {
        if availablePermits > 0 {
            availablePermits -= 1
            return true
        }
        let id = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard !Task.isCancelled else {
                    continuation.resume(returning: false)
                    return
                }
                waiters.append(Waiter(id: id, continuation: continuation))
            }
        } onCancel: { [self] in
            Task {
                await cancelAcquisition(id)
            }
        }
    }

    private func cancelAcquisition(_ id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        let waiter = waiters.remove(at: index)
        waiter.continuation.resume(returning: false)
    }

    private func release() {
        guard !waiters.isEmpty else {
            availablePermits += 1
            return
        }
        let waiter = waiters.removeFirst()
        waiter.continuation.resume(returning: true)
    }
}
