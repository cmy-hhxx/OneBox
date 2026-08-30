import Foundation

protocol AnonymousSessionProviding: AnyObject, Sendable {
    func cookieFile(for source: SupportedSource) async throws -> URL?
    func hasVerificationCookie(for source: SupportedSource) async -> Bool
    func discard() async
}
