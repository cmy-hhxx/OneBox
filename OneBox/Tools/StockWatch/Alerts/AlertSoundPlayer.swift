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

    nonisolated static func resourceName(for direction: AlertDirection) -> String {
        switch direction {
        case .rising:
            "bull-moo"
        case .falling:
            "bear-growl"
        }
    }

    func play(_ direction: AlertDirection, isEnabled: Bool) {
        platform.stopAlertSound()
        guard isEnabled else { return }
        platform.playAlertSound(
            named: Self.resourceName(for: direction),
            fileExtension: "wav"
        )
    }

    func stop() {
        platform.stopAlertSound()
    }
}

@MainActor
final class NoOpAlertSoundPlayer: AlertSoundPlaying {
    func play(_ direction: AlertDirection, isEnabled: Bool) {}
    func stop() {}
}
