import Foundation

@MainActor
public protocol StockWatchPlatformClient: AnyObject {
    @discardableResult
    func copyText(_ text: String) -> Bool

    @discardableResult
    func revealDirectory(_ directory: URL) -> Bool

    @discardableResult
    func playAlertSound(at fileURL: URL) -> Bool

    func stopAlertSound()
}
