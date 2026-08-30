import Foundation

protocol MarketDataClient: Sendable {
    func searchInstruments(matching query: String) async throws -> [Instrument]
    func fetchQuote(for instrument: Instrument) async throws -> QuoteSnapshot
}

enum MarketDataError: LocalizedError {
    case invalidURL
    case invalidResponse
    case noIntradayData
    case provider(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            tr("行情地址无效")
        case .invalidResponse:
            tr("行情返回格式异常")
        case .noIntradayData:
            tr("今天暂无分时数据")
        case .provider(let message):
            message
        }
    }
}
