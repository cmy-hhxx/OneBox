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

    func playAlertSound(at fileURL: URL) -> Bool {
        currentSound?.stop()
        guard let sound = NSSound(contentsOf: fileURL, byReference: true) else {
            currentSound = nil
            NSSound.beep()
            return false
        }
        sound.volume = 0.82
        currentSound = sound
        return sound.play()
    }

    func stopAlertSound() {
        currentSound?.stop()
        currentSound = nil
    }
}
