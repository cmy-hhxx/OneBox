import AppKit
import StockWatchTool

@MainActor
final class MacStockWatchPlatformClient: StockWatchPlatformClient {
    private var currentSound: NSSound?

    func copyText(_ text: String) -> Bool {
        NSPasteboard.general.clearContents()
        return NSPasteboard.general.setString(text, forType: .string)
    }

    func revealDirectory(_ directory: URL) -> Bool {
        NSWorkspace.shared.open(directory)
    }

    func playAlertSound(named resourceName: String, fileExtension: String) -> Bool {
        guard
            let url = Bundle.main.url(
                forResource: resourceName,
                withExtension: fileExtension
            )
        else {
            NSSound.beep()
            return false
        }

        currentSound?.stop()
        currentSound = NSSound(contentsOf: url, byReference: true)
        currentSound?.volume = 0.82
        return currentSound?.play() ?? false
    }

    func stopAlertSound() {
        currentSound?.stop()
        currentSound = nil
    }
}
