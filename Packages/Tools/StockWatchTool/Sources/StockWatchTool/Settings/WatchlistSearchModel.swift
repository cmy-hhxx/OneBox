import Combine
import Foundation

@MainActor
final class WatchlistSearchModel: ObservableObject {
    @Published var query = "" {
        didSet {
            guard query != oldValue else { return }
            invalidateSearch()
        }
    }
    @Published private(set) var results: [Instrument] = []
    @Published private(set) var isSearching = false
    @Published private(set) var message: String?
    private(set) var hasSearchFailure = false

    private let search: (String) async throws -> [Instrument]
    private var searchTask: Task<Void, Never>?
    private var requestRevision = 0

    init(search: @escaping (String) async throws -> [Instrument]) {
        self.search = search
    }

    deinit {
        searchTask?.cancel()
    }

    func submit() {
        let cleanQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanQuery.isEmpty else {
            cancel()
            return
        }

        requestRevision += 1
        let revision = requestRevision
        searchTask?.cancel()
        if !results.isEmpty {
            results = []
        }
        if message != nil {
            message = nil
        }
        hasSearchFailure = false
        if !isSearching {
            isSearching = true
        }

        let search = search
        searchTask = Task { [weak self] in
            do {
                let found = try await search(cleanQuery)
                guard !Task.isCancelled else { return }
                self?.applyResults(found, revision: revision)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                self?.applyFailure(error, revision: revision)
            }
        }
    }

    func cancel() {
        invalidateSearch()
    }

    var isPresentingSearch: Bool {
        isSearching || !results.isEmpty || message != nil
    }

    private func invalidateSearch() {
        requestRevision += 1
        searchTask?.cancel()
        searchTask = nil
        if !results.isEmpty {
            results = []
        }
        if message != nil {
            message = nil
        }
        hasSearchFailure = false
        if isSearching {
            isSearching = false
        }
    }

    private func applyResults(_ found: [Instrument], revision: Int) {
        guard revision == requestRevision else { return }
        let deduplicated = Self.deduplicated(found)
        if results != deduplicated {
            results = deduplicated
        }
        let resultMessage =
            deduplicated.isEmpty
            ? tr("没有找到支持的 A股、港股或美股")
            : nil
        hasSearchFailure = false
        if message != resultMessage {
            message = resultMessage
        }
        if isSearching {
            isSearching = false
        }
        searchTask = nil
    }

    private func applyFailure(_ error: Error, revision: Int) {
        guard revision == requestRevision else { return }
        hasSearchFailure = true
        let failureMessage = String(
            format: tr("搜索失败：%@"),
            error.localizedDescription
        )
        if message != failureMessage {
            message = failureMessage
        }
        if isSearching {
            isSearching = false
        }
        searchTask = nil
    }

    private static func deduplicated(_ instruments: [Instrument]) -> [Instrument] {
        var seen = Set<InstrumentID>()
        return instruments.filter { seen.insert($0.id).inserted }
    }
}
