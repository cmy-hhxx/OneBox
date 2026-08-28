@preconcurrency import AVFoundation
import Foundation
@preconcurrency import MediaPlayer
import OneBoxRuntime

@MainActor
public protocol PodPinPlatformProviding {
    var legacyPreferences: UserDefaults { get }
    var fileManager: FileManager { get }
    var remoteCommandCenter: MPRemoteCommandCenter { get }
    var nowPlayingInfoCenter: MPNowPlayingInfoCenter { get }
    func makeAudioPlayer(item: AVPlayerItem) -> AVPlayer
}

@MainActor
public enum PodPinModule {
    public static func makeRegistration(
        platform: any PodPinPlatformProviding
    ) -> ToolRegistration {
        let session = PodPinModuleSession(platform: platform)
        return ToolRegistration(
            id: ToolID(rawValue: "podpin"),
            displayName: "PodPin",
            onApplicationTermination: {
                await session.shutdown()
            },
            content: {
                PodPinToolRoot(session: session)
            }
        )
    }
}

@MainActor
final class PodPinModuleSession {
    private let platform: any PodPinPlatformProviding
    private var lifecycle: PodPinToolLifecycle?
    private var shutdownTask: Task<Void, Never>?

    var hasActiveLifecycle: Bool { lifecycle != nil }

    init(platform: any PodPinPlatformProviding) {
        self.platform = platform
    }

    func contentLifecycle() -> PodPinToolLifecycle {
        if let lifecycle {
            return lifecycle
        }
        let lifecycle = PodPinToolLifecycle(platform: platform)
        self.lifecycle = lifecycle
        return lifecycle
    }

    func shutdown() async {
        if let shutdownTask {
            await withTaskCancellationHandler {
                await shutdownTask.value
            } onCancel: {
                shutdownTask.cancel()
            }
            return
        }
        guard let lifecycle else { return }

        let task = Task { @MainActor in
            await lifecycle.store.shutdown()
        }
        shutdownTask = task
        await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
        if self.lifecycle === lifecycle {
            self.lifecycle = nil
        }
        shutdownTask = nil
    }
}
