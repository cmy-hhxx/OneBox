import Foundation
import SwiftUI

/// Startup opens persistence off the main actor. The `@Sendable` factories use
/// this wrapper to carry the injected, thread-safe `FileManager` reference.
final class PodPinFileManagerReference: @unchecked Sendable {
    let value: FileManager

    init(_ value: FileManager) {
        self.value = value
    }
}

@MainActor
struct PodPinToolRoot: View {
    private let lifecycle: PodPinToolLifecycle

    init(session: PodPinModuleSession) {
        lifecycle = session.contentLifecycle()
    }

    var body: some View {
        PodPinLibraryView()
            .environmentObject(lifecycle.store)
            .environmentObject(lifecycle.navigator)
            .task {
                await lifecycle.store.resumeUI()
                while !Task.isCancelled {
                    do {
                        try await Task.sleep(for: .seconds(3_600))
                    } catch {
                        break
                    }
                }
                lifecycle.store.suspendUI()
            }
            .onDisappear {
                lifecycle.store.suspendUI()
            }
    }
}

@MainActor
final class PodPinToolLifecycle {
    let store: PodPinStore
    let navigator = AppNavigator()

    init(platform: any PodPinPlatformProviding) {
        let fileManager = platform.fileManager
        let fileManagerReference = PodPinFileManagerReference(fileManager)
        store = PodPinStore(
            preferences: AppPreferences(defaults: platform.legacyPreferences),
            databaseFactory: {
                try MarketDatabase.openInApplicationSupport(
                    fileManager: fileManagerReference.value
                )
            },
            mediaStoreFactory: {
                try PodPinMediaStore.inApplicationSupport(fileManager: fileManagerReference.value)
            },
            browserAccessAuthorizer: BrowserAccessBroker(reference: fileManagerReference),
            playbackController: AudioPlaybackController(playerFactory: platform.makeAudioPlayer),
            nowPlayingController: NowPlayingController(
                commandCenter: platform.remoteCommandCenter,
                nowPlayingInfoCenter: platform.nowPlayingInfoCenter
            )
        )
    }
}
