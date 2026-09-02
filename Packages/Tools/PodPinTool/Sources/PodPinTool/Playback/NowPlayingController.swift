import AppKit
import CoreGraphics
@preconcurrency import MediaPlayer

struct NowPlayingDecodedArtwork: @unchecked Sendable {
    let image: CGImage
}

/// MediaPlayer invokes artwork request handlers on its own queue. Keep the
/// immutable image in an explicitly unchecked box so the handler itself stays
/// nonisolated rather than inheriting `NowPlayingController`'s main actor.
private final class NowPlayingArtworkImageBox: @unchecked Sendable {
    let image: NSImage

    @MainActor
    init(image: NSImage) {
        self.image = image
    }
}

private func nowPlayingArtworkRequestHandler(
    imageBox: NowPlayingArtworkImageBox
) -> @Sendable (CGSize) -> NSImage {
    { _ in imageBox.image }
}

@MainActor
final class NowPlayingController {
    private struct ArtworkKey: Equatable {
        let itemID: UUID
        let path: String?
    }

    private struct StaticMetadataKey: Equatable {
        let itemID: UUID
        let title: String
        let author: String?
        let duration: TimeInterval
        let artworkPath: String?
    }

    private let commandCenter: MPRemoteCommandCenter?
    private let nowPlayingInfoCenter: MPNowPlayingInfoCenter?
    private let artworkLoader: @Sendable (URL) async -> NowPlayingDecodedArtwork?
    private let timeoutTaskOwner = CooperativeTaskOwner()
    private var commandTargets: [(MPRemoteCommand, Any)] = []
    private var artworkLoadTask: Task<Void, Never>?
    private var cachedArtworkKey: ArtworkKey?
    private var cachedArtwork: MPMediaItemArtwork?
    private var staticMetadataKey: StaticMetadataKey?
    private var staticInfo: [String: Any] = [:]
    private var playbackStateRawValue: UInt?

    var onPlay: (() -> Void)?
    var onPause: (() -> Void)?
    var onTogglePlayback: (() -> Void)?
    var onSkipBackward: (() -> Void)?
    var onSkipForward: (() -> Void)?
    var onSeek: ((TimeInterval) -> Void)?
    var onChangeRate: ((Double) -> Void)?

    init(
        artworkLoader: @escaping @Sendable (URL) async -> NowPlayingDecodedArtwork? = {
            guard let image = await ArtworkImageDecoder.thumbnail(at: $0, maxPixelSize: 1_024)
            else { return nil }
            return NowPlayingDecodedArtwork(image: image)
        }
    ) {
        commandCenter = nil
        nowPlayingInfoCenter = nil
        self.artworkLoader = artworkLoader
    }

    init(
        commandCenter: MPRemoteCommandCenter,
        nowPlayingInfoCenter: MPNowPlayingInfoCenter,
        artworkLoader: @escaping @Sendable (URL) async -> NowPlayingDecodedArtwork? = {
            guard let image = await ArtworkImageDecoder.thumbnail(at: $0, maxPixelSize: 1_024)
            else { return nil }
            return NowPlayingDecodedArtwork(image: image)
        }
    ) {
        self.commandCenter = commandCenter
        self.nowPlayingInfoCenter = nowPlayingInfoCenter
        self.artworkLoader = artworkLoader
    }

    var installedCommandHandlerCount: Int { commandTargets.count }

    func waitForPendingArtwork() async {
        await artworkLoadTask?.value
    }

    func activate() {
        guard commandCenter != nil, commandTargets.isEmpty else { return }
        installCommandHandlers()
    }

    func deactivate() async {
        artworkLoadTask?.cancel()
        timeoutTaskOwner.cancelAll()
        if let artworkLoadTask {
            await artworkLoadTask.value
        }
        _ = await timeoutTaskOwner.cancelAndWait(upTo: .seconds(1))
        self.artworkLoadTask = nil
        removeCommandHandlers()
        if let commandCenter {
            commandCenter.playCommand.isEnabled = false
            commandCenter.pauseCommand.isEnabled = false
            commandCenter.togglePlayPauseCommand.isEnabled = false
            commandCenter.skipBackwardCommand.isEnabled = false
            commandCenter.skipForwardCommand.isEnabled = false
            commandCenter.changePlaybackPositionCommand.isEnabled = false
            commandCenter.changePlaybackRateCommand.isEnabled = false
        }

        nowPlayingInfoCenter?.nowPlayingInfo = nil
        nowPlayingInfoCenter?.playbackState = .stopped
        cachedArtworkKey = nil
        cachedArtwork = nil
        staticMetadataKey = nil
        staticInfo = [:]
        playbackStateRawValue = nil
    }

    func publish(
        item: AudioItem?,
        time: TimeInterval,
        duration: TimeInterval,
        rate: Double,
        isPlaying: Bool,
        artworkURL: URL? = nil
    ) {
        guard let item else {
            artworkLoadTask?.cancel()
            artworkLoadTask = nil
            cachedArtworkKey = nil
            cachedArtwork = nil
            staticMetadataKey = nil
            staticInfo = [:]
            nowPlayingInfoCenter?.nowPlayingInfo = nil
            publishPlaybackState(.stopped)
            return
        }

        let artworkPath = artworkURL?.absoluteString
        let metadataKey = StaticMetadataKey(
            itemID: item.id,
            title: item.title,
            author: item.author,
            duration: duration.isFinite && duration > 0 ? duration : 0,
            artworkPath: artworkPath
        )
        if staticMetadataKey != metadataKey {
            staticMetadataKey = metadataKey
            requestArtwork(
                for: item.id,
                url: artworkURL,
                path: artworkPath,
                metadataKey: metadataKey
            )
            staticInfo = makeStaticInfo(for: item, duration: duration)
        }

        var info = staticInfo
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = max(time, 0)
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? rate : 0
        info[MPNowPlayingInfoPropertyDefaultPlaybackRate] = rate
        nowPlayingInfoCenter?.nowPlayingInfo = info
        publishPlaybackState(isPlaying ? .playing : .paused)
    }

    private func makeStaticInfo(
        for item: AudioItem,
        duration: TimeInterval
    ) -> [String: Any] {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: item.title,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
        ]
        if let author = item.author, !author.isEmpty {
            info[MPMediaItemPropertyArtist] = author
        }
        if duration.isFinite, duration > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = duration
        }
        if let cachedArtwork {
            info[MPMediaItemPropertyArtwork] = cachedArtwork
        }
        return info
    }

    private func requestArtwork(
        for itemID: UUID,
        url: URL?,
        path: String?,
        metadataKey: StaticMetadataKey
    ) {
        let key = ArtworkKey(itemID: itemID, path: path)
        guard cachedArtworkKey != key else { return }

        artworkLoadTask?.cancel()
        cachedArtworkKey = key
        cachedArtwork = nil
        guard let url else {
            artworkLoadTask = nil
            return
        }

        let artworkLoader = artworkLoader
        let timeoutTaskOwner = timeoutTaskOwner
        artworkLoadTask = Task { @MainActor [weak self] in
            let result = await withCooperativeTimeout(
                .seconds(2),
                owner: timeoutTaskOwner
            ) {
                await artworkLoader(url)
            }
            guard !Task.isCancelled,
                case .value(let decoded?) = result,
                let self,
                self.staticMetadataKey == metadataKey,
                self.cachedArtworkKey == key
            else { return }

            let image = NSImage(
                cgImage: decoded.image,
                size: NSSize(width: decoded.image.width, height: decoded.image.height)
            )
            let imageBox = NowPlayingArtworkImageBox(image: image)
            let artwork = MPMediaItemArtwork(
                boundsSize: image.size,
                requestHandler: nowPlayingArtworkRequestHandler(imageBox: imageBox)
            )
            self.cachedArtwork = artwork
            self.staticInfo[MPMediaItemPropertyArtwork] = artwork
            if var info = self.nowPlayingInfoCenter?.nowPlayingInfo {
                info[MPMediaItemPropertyArtwork] = artwork
                self.nowPlayingInfoCenter?.nowPlayingInfo = info
            }
        }
    }

    private func publishPlaybackState(_ state: MPNowPlayingPlaybackState) {
        guard playbackStateRawValue != state.rawValue else { return }
        playbackStateRawValue = state.rawValue
        nowPlayingInfoCenter?.playbackState = state
    }

    private func installCommandHandlers() {
        guard let commandCenter else { return }
        commandCenter.playCommand.isEnabled = true
        add(commandCenter.playCommand) { [weak self] _ in
            guard let onPlay = self?.onPlay else { return .commandFailed }
            onPlay()
            return .success
        }
        commandCenter.pauseCommand.isEnabled = true
        add(commandCenter.pauseCommand) { [weak self] _ in
            guard let onPause = self?.onPause else { return .commandFailed }
            onPause()
            return .success
        }
        commandCenter.togglePlayPauseCommand.isEnabled = true
        add(commandCenter.togglePlayPauseCommand) { [weak self] _ in
            self?.onTogglePlayback?()
            return .success
        }

        commandCenter.skipBackwardCommand.isEnabled = true
        commandCenter.skipBackwardCommand.preferredIntervals = [15]
        add(commandCenter.skipBackwardCommand) { [weak self] _ in
            self?.onSkipBackward?()
            return .success
        }
        commandCenter.skipForwardCommand.isEnabled = true
        commandCenter.skipForwardCommand.preferredIntervals = [30]
        add(commandCenter.skipForwardCommand) { [weak self] _ in
            self?.onSkipForward?()
            return .success
        }
        commandCenter.changePlaybackPositionCommand.isEnabled = true
        add(commandCenter.changePlaybackPositionCommand) { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            self?.onSeek?(event.positionTime)
            return .success
        }
        commandCenter.changePlaybackRateCommand.isEnabled = true
        commandCenter.changePlaybackRateCommand.supportedPlaybackRates = AppPreferences
            .supportedPlaybackRates.map(NSNumber.init(value:))
        add(commandCenter.changePlaybackRateCommand) { [weak self] event in
            guard let event = event as? MPChangePlaybackRateCommandEvent else {
                return .commandFailed
            }
            self?.onChangeRate?(Double(event.playbackRate))
            return .success
        }
    }

    private func add(
        _ command: MPRemoteCommand,
        handler: @escaping (MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus
    ) {
        let target = command.addTarget(handler: handler)
        commandTargets.append((command, target))
    }

    private func removeCommandHandlers() {
        for (command, target) in commandTargets {
            command.removeTarget(target)
        }
        commandTargets.removeAll()
    }
}
