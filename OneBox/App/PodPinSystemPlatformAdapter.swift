@preconcurrency import AVFoundation
import Foundation
@preconcurrency import MediaPlayer
import PodPinTool

@MainActor
struct PodPinSystemPlatformAdapter: PodPinPlatformProviding {
    var legacyPreferences: UserDefaults {
        UserDefaults(suiteName: "io.github.cmy-hhxx.podpin") ?? .standard
    }

    var fileManager: FileManager { .default }
    var remoteCommandCenter: MPRemoteCommandCenter { .shared() }
    var nowPlayingInfoCenter: MPNowPlayingInfoCenter { .default() }

    func makeAudioPlayer(item: AVPlayerItem) -> AVPlayer {
        AVPlayer(playerItem: item)
    }
}
