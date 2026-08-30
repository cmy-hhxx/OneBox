import Foundation

@MainActor
protocol AlertSoundPlaying: AnyObject {
    func play(_ direction: AlertDirection, isEnabled: Bool)
    func stop()
}

@MainActor
final class AlertSoundPlayer: AlertSoundPlaying {
    private let platform: any StockWatchPlatformClient

    init(platform: any StockWatchPlatformClient) {
        self.platform = platform
    }

    nonisolated static func resourceURL(for direction: AlertDirection) -> URL? {
        Bundle.module.url(
            forResource: resourceName(for: direction),
            withExtension: "wav"
        )
    }

    func play(_ direction: AlertDirection, isEnabled: Bool) {
        platform.stopAlertSound()
        guard
            isEnabled,
            let fileURL = Self.resourceURL(for: direction)
        else { return }
        platform.playAlertSound(at: fileURL)
    }

    func stop() {
        platform.stopAlertSound()
    }

    private nonisolated static func resourceName(for direction: AlertDirection) -> String {
        switch direction {
        case .rising:
            "bull-moo"
        case .falling:
            "bear-growl"
        }
    }
}

@MainActor
final class NoOpAlertSoundPlayer: AlertSoundPlaying {
    func play(_ direction: AlertDirection, isEnabled: Bool) {}
    func stop() {}
}
