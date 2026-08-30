@preconcurrency import AVFoundation
import Foundation
@preconcurrency import MediaPlayer
import PodPinTool

@MainActor
struct PodPinSystemPlatformAdapter: PodPinPlatformProviding {
    let debugFixtureAudioURL: URL?
    let externalToolsDirectoryURL: URL?

    init(bundle: Bundle = .main) {
        #if DEBUG
            debugFixtureAudioURL = bundle.url(
                forResource: "podpin-sample",
                withExtension: "m4a"
            )
        #else
            debugFixtureAudioURL = nil
        #endif
        externalToolsDirectoryURL = bundle.resourceURL?.appending(
            path: "Tools",
            directoryHint: .isDirectory
        )
    }

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
