@preconcurrency import AVFoundation
import Combine
import Foundation
import OSLog

/// The player lifecycle exposed to presentation layers. `replayPending` is an
/// intentional, short-lived boundary: it prevents a completed item's replay
/// control from issuing more than one reset seek.
enum PlaybackPhase: Equatable {
    case idle
    case loading
    case buffering
    case paused
    case playing
    case finished
    case replayPending
    case failed(String)

    var isPlaying: Bool {
        self == .playing
    }

    var hasPlaybackIntent: Bool {
        switch self {
        case .playing, .buffering, .replayPending:
            true
        case .idle, .loading, .paused, .finished, .failed:
            false
        }
    }
}

@MainActor
final class AudioPlaybackController: NSObject, ObservableObject {
    typealias State = PlaybackPhase

    private enum PlaybackStartOutcome {
        case audible
        case cancelled
        case failed
    }

    private static let performanceSignposter = OSSignposter(
        subsystem: "com.cmy.OneBox",
        category: "PodPin"
    )

    @Published private(set) var state: PlaybackPhase = .idle
    @Published private(set) var currentItem: AudioItem?
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var rate: Double = 1
    @Published private(set) var volume: Double = 1
    private(set) var listeningHistory = ListeningHistory()
    private(set) var outputRevision = 0

    var onPlaybackPositionChanged: ((UUID, TimeInterval, ListeningHistory, Bool) -> Void)?
    var onStateChanged: (() -> Void)?
    var onPlaybackReady: ((UUID) -> Void)?
    var onPlaybackFailed: ((UUID, String, Int?) -> Void)?
    var onOutputChanged: (() -> Void)?
    /// Called exactly once for the active player-item end notification. The
    /// store owns the policy for advancing persistent playback queues.
    var onPlaybackFinished: ((UUID) -> Void)?

    private let playerFactory: (AVPlayerItem) -> AVPlayer
    private var player: AVPlayer?
    private var timeObserver: Any?
    private var statusObservation: NSKeyValueObservation?
    private var durationObservation: NSKeyValueObservation?
    private var timeControlObservation: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?
    private var lastPersistedSecond: Int = -1
    private var shouldAutoplayWhenReady = false
    private var didEmitPlaybackFinished = false
    private var startupInterval: OSSignpostIntervalState?
    private var startupItemID: UUID?
    private var startupRequestToken: UUID?
    private var lastAudibleTime: TimeInterval?
    private var isSeeking = false

    #if DEBUG || PODPIN_TESTING
        private(set) var cancelledPlaybackStartCount = 0
    #endif

    override convenience init() {
        self.init(playerFactory: { AVPlayer(playerItem: $0) })
    }

    init(playerFactory: @escaping (AVPlayerItem) -> AVPlayer) {
        self.playerFactory = playerFactory
        super.init()
    }

    var isPlaying: Bool { state.isPlaying }
    var routePlayer: AVPlayer? { player }

    func load(
        item: AudioItem,
        url: URL,
        headers: [String: String] = [:],
        mimeType: String? = nil,
        resumeAt: TimeInterval? = nil,
        autoplay: Bool = false
    ) {
        if let player {
            captureCurrentAudibleTime(using: player)
        }
        persistPosition(force: true)
        let preservesStartupInterval =
            autoplay && startupInterval != nil && startupItemID == item.id
        tearDownPlayer(preservingStartupInterval: preservesStartupInterval)
        if autoplay, !preservesStartupInterval {
            _ = beginPlaybackStart(for: item.id)
        }
        currentItem = item
        currentTime = 0
        duration = item.duration ?? 0
        listeningHistory = item.listeningHistory
        state = .loading
        lastPersistedSecond = -1
        shouldAutoplayWhenReady = autoplay
        didEmitPlaybackFinished = false
        notifyStateChanged()

        let asset: AVURLAsset
        if headers.isEmpty, mimeType == nil {
            asset = AVURLAsset(url: url)
        } else {
            var options: [String: Any] = ["AVURLAssetHTTPHeaderFieldsKey": headers]
            options[AVURLAssetOverrideMIMETypeKey] = mimeType
            asset = AVURLAsset(url: url, options: options)
        }
        let playerItem = AVPlayerItem(asset: asset)
        let player = playerFactory(playerItem)
        player.volume = Float(volume)
        self.player = player
        notifyOutputChanged()
        let itemID = item.id
        statusObservation = playerItem.observe(\.status, options: [.initial, .new]) {
            [weak self, weak player, weak playerItem] observedItem, _ in
            Task { @MainActor [weak self] in
                guard let self,
                    let player,
                    let playerItem,
                    observedItem === playerItem,
                    self.isCurrent(player: player, playerItem: playerItem, itemID: itemID)
                else {
                    return
                }
                switch observedItem.status {
                case .readyToPlay:
                    Self.performanceSignposter.emitEvent("player.ready")
                    self.duration = observedItem.duration.secondsIfFinite ?? self.duration
                    self.onPlaybackReady?(itemID)
                    let target = self.clampedTime(resumeAt ?? 0)
                    if target > 0 {
                        self.seek(to: target, autoplayAfterSeek: self.shouldAutoplayWhenReady)
                    } else if self.shouldAutoplayWhenReady {
                        self.play()
                    } else {
                        self.state = .paused
                        self.notifyStateChanged()
                    }
                case .failed:
                    self.failPlayback(
                        itemID: itemID,
                        message: observedItem.error?.localizedDescription ?? "音频无法播放。",
                        statusCode: observedItem.errorLog()?.events.last?.errorStatusCode
                    )
                case .unknown:
                    break
                @unknown default:
                    self.failPlayback(itemID: itemID, message: "音频状态不可用。", statusCode: nil)
                }
            }
        }
        durationObservation = playerItem.observe(\.duration, options: [.new]) {
            [weak self, weak player, weak playerItem] observedItem, _ in
            Task { @MainActor [weak self] in
                guard let self,
                    let player,
                    let playerItem,
                    observedItem === playerItem,
                    self.isCurrent(player: player, playerItem: playerItem, itemID: itemID)
                else {
                    return
                }
                self.duration = observedItem.duration.secondsIfFinite ?? self.duration
                self.notifyStateChanged()
            }
        }
        timeControlObservation = player.observe(\.timeControlStatus, options: [.initial, .new]) {
            [weak self, weak player, weak playerItem] statusPlayer, _ in
            Task { @MainActor [weak self] in
                guard let self,
                    let player,
                    let playerItem,
                    statusPlayer === player,
                    self.isCurrent(player: player, playerItem: playerItem, itemID: itemID)
                else {
                    return
                }
                self.updatePlaybackState(for: player)
            }
        }
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { [weak self, weak player, weak playerItem] time in
            Task { @MainActor [weak self] in
                guard let self, let player, let playerItem else { return }
                self.updateTime(
                    time.secondsIfFinite ?? 0,
                    for: player,
                    playerItem: playerItem,
                    itemID: itemID
                )
            }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { [weak self, weak player, weak playerItem] _ in
            Task { @MainActor [weak self] in
                guard let self,
                    let player,
                    let playerItem,
                    self.isCurrent(player: player, playerItem: playerItem, itemID: itemID),
                    !self.didEmitPlaybackFinished
                else {
                    return
                }
                self.didEmitPlaybackFinished = true
                self.recordAudibleProgress(to: self.duration)
                self.currentTime = self.duration
                self.lastAudibleTime = nil
                self.state = .finished
                self.endStartupInterval(.audible)
                self.persistPosition(force: true)
                self.onPlaybackFinished?(itemID)
                self.notifyStateChanged()
            }
        }
    }

    func play() {
        guard let player, player.currentItem != nil, let currentItem else { return }
        beginPlaybackStartIfNeeded(for: currentItem.id)
        if state == .finished {
            didEmitPlaybackFinished = false
            shouldAutoplayWhenReady = true
            state = .replayPending
            notifyStateChanged()
            seek(to: 0, autoplayAfterSeek: true)
            return
        }
        guard state != .replayPending else { return }
        beginPlayback(using: player)
    }

    func pause() {
        guard let player, currentItem != nil else { return }
        captureCurrentAudibleTime(using: player)
        shouldAutoplayWhenReady = false
        player.pause()
        lastAudibleTime = nil
        if state != .finished {
            state = .paused
        }
        endStartupInterval(.cancelled)
        persistPosition(force: true)
        notifyStateChanged()
    }

    func togglePlayback() {
        state.hasPlaybackIntent ? pause() : play()
    }

    func skipBackward() {
        seek(to: currentTime - 15)
    }

    func skipForward() {
        seek(to: currentTime + 30)
    }

    func seek(to proposedTime: TimeInterval, autoplayAfterSeek: Bool? = nil) {
        guard let player, let playerItem = player.currentItem, let itemID = currentItem?.id else {
            return
        }
        let target = clampedTime(proposedTime)
        let shouldResume = autoplayAfterSeek ?? state.hasPlaybackIntent
        captureCurrentAudibleTime(using: player)
        lastAudibleTime = nil
        isSeeking = true
        let tolerance: CMTime =
            target == 0
            ? .zero
            : CMTime(seconds: 0.25, preferredTimescale: 600)
        player.seek(
            to: CMTime(seconds: target, preferredTimescale: 600),
            toleranceBefore: tolerance,
            toleranceAfter: tolerance
        ) { [weak self, weak player, weak playerItem] finished in
            Task { @MainActor [weak self] in
                guard let self,
                    let player,
                    let playerItem,
                    self.isCurrent(player: player, playerItem: playerItem, itemID: itemID)
                else {
                    return
                }
                self.isSeeking = false
                guard finished else {
                    self.lastAudibleTime = nil
                    self.notifyStateChanged()
                    return
                }
                self.currentTime = player.currentTime().secondsIfFinite ?? target
                self.persistPosition(force: true)
                if shouldResume && self.shouldAutoplayWhenReady {
                    self.beginPlayback(using: player)
                } else {
                    if self.state == .loading || self.state == .buffering || self.state == .finished
                        || self.state == .replayPending
                    {
                        self.state = .paused
                    }
                    self.notifyStateChanged()
                }
            }
        }
    }

    func setRate(_ newRate: Double) {
        guard [0.75, 1, 1.25, 1.5, 2].contains(newRate) else { return }
        rate = newRate
        if state.hasPlaybackIntent {
            player?.rate = Float(newRate)
        }
        notifyStateChanged()
    }

    func setVolume(_ newVolume: Double) {
        let normalized = min(max(newVolume.isFinite ? newVolume : 1, 0), 1)
        guard normalized != volume else { return }
        volume = normalized
        player?.volume = Float(normalized)
        notifyOutputChanged()
    }

    func stop() {
        pause()
        tearDownPlayer()
        currentItem = nil
        currentTime = 0
        duration = 0
        listeningHistory = ListeningHistory()
        state = .idle
        notifyStateChanged()
    }

    func flushPlaybackPosition() {
        if let player {
            captureCurrentAudibleTime(using: player)
        }
        persistPosition(force: true)
    }

    private func updateTime(
        _ time: TimeInterval,
        for player: AVPlayer,
        playerItem: AVPlayerItem,
        itemID: UUID
    ) {
        guard isCurrent(player: player, playerItem: playerItem, itemID: itemID) else { return }
        currentTime = clampedTime(time)
        if state == .playing, !isSeeking {
            recordAudibleProgress(to: currentTime)
            lastAudibleTime = currentTime
        } else {
            lastAudibleTime = nil
        }
        let second = Int(currentTime.rounded(.down))
        if second / 5 != lastPersistedSecond / 5 {
            persistPosition(force: false)
            lastPersistedSecond = second
        }
        notifyStateChanged()
    }

    private func beginPlayback(using player: AVPlayer) {
        shouldAutoplayWhenReady = true
        lastAudibleTime = nil
        state = .buffering
        notifyStateChanged()
        player.playImmediately(atRate: Float(rate))
    }

    private func failPlayback(itemID: UUID, message: String, statusCode: Int?) {
        guard currentItem?.id == itemID else { return }
        if case .failed = state { return }
        if let player {
            captureCurrentAudibleTime(using: player)
        }
        lastAudibleTime = nil
        state = .failed(message)
        endStartupInterval(.failed)
        onPlaybackFailed?(itemID, message, statusCode)
        notifyStateChanged()
    }

    private func isCurrent(
        player candidatePlayer: AVPlayer,
        playerItem candidatePlayerItem: AVPlayerItem,
        itemID: UUID
    ) -> Bool {
        player === candidatePlayer
            && candidatePlayer.currentItem === candidatePlayerItem
            && currentItem?.id == itemID
    }

    private func persistPosition(force: Bool) {
        guard let item = currentItem else { return }
        if force || currentTime.isFinite {
            onPlaybackPositionChanged?(item.id, currentTime, listeningHistory, force)
        }
    }

    private func captureCurrentAudibleTime(using player: AVPlayer) {
        guard state == .playing, !isSeeking else { return }
        let time = clampedTime(player.currentTime().secondsIfFinite ?? currentTime)
        recordAudibleProgress(to: time)
        currentTime = time
    }

    private func recordAudibleProgress(to time: TimeInterval) {
        guard let start = lastAudibleTime else {
            lastAudibleTime = clampedTime(time)
            return
        }
        listeningHistory.record(from: start, to: clampedTime(time), duration: duration)
    }

    private func clampedTime(_ time: TimeInterval) -> TimeInterval {
        let maximum = duration > 0 ? duration : .greatestFiniteMagnitude
        return min(max(time.isFinite ? time : 0, 0), maximum)
    }

    @discardableResult
    func beginPlaybackStart(for itemID: UUID) -> UUID {
        endStartupInterval(.cancelled)
        let requestToken = UUID()
        startupItemID = itemID
        startupRequestToken = requestToken
        startupInterval = Self.performanceSignposter.beginInterval("PlaybackStart")
        return requestToken
    }

    @discardableResult
    private func beginPlaybackStartIfNeeded(for itemID: UUID) -> UUID {
        if startupItemID == itemID,
            startupInterval != nil,
            let startupRequestToken
        {
            return startupRequestToken
        }
        return beginPlaybackStart(for: itemID)
    }

    @discardableResult
    func cancelPlaybackStart(_ requestToken: UUID) -> Bool {
        guard startupRequestToken == requestToken else { return false }
        endStartupInterval(.cancelled)
        return true
    }

    private func tearDownPlayer(preservingStartupInterval: Bool = false) {
        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
        statusObservation?.invalidate()
        statusObservation = nil
        durationObservation?.invalidate()
        durationObservation = nil
        timeControlObservation?.invalidate()
        timeControlObservation = nil
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        endObserver = nil
        player?.pause()
        player = nil
        if !preservingStartupInterval {
            endStartupInterval(.cancelled)
        }
        notifyOutputChanged()
        shouldAutoplayWhenReady = false
        lastAudibleTime = nil
        isSeeking = false
    }

    private func notifyStateChanged() {
        onStateChanged?()
    }

    private func notifyOutputChanged() {
        outputRevision &+= 1
        onOutputChanged?()
    }

    private func updatePlaybackState(for player: AVPlayer) {
        guard shouldAutoplayWhenReady else { return }

        switch player.timeControlStatus {
        case .playing:
            guard state != .playing else { return }
            state = .playing
            lastAudibleTime =
                isSeeking
                ? nil
                : clampedTime(player.currentTime().secondsIfFinite ?? currentTime)
            Self.performanceSignposter.emitEvent("audio.audible")
            endStartupInterval(.audible)
            notifyStateChanged()
        case .waitingToPlayAtSpecifiedRate:
            guard state != .buffering else { return }
            captureCurrentAudibleTime(using: player)
            lastAudibleTime = nil
            state = .buffering
            notifyStateChanged()
        case .paused:
            break
        @unknown default:
            break
        }
    }

    private func endStartupInterval(_ outcome: PlaybackStartOutcome) {
        guard let startupInterval else { return }
        switch outcome {
        case .audible:
            Self.performanceSignposter.endInterval("PlaybackStart", startupInterval)
        case .cancelled:
            #if DEBUG || PODPIN_TESTING
                cancelledPlaybackStartCount += 1
            #endif
            Self.performanceSignposter.endInterval(
                "PlaybackStart",
                startupInterval,
                "cancelled"
            )
        case .failed:
            Self.performanceSignposter.endInterval(
                "PlaybackStart",
                startupInterval,
                "failed"
            )
        }
        self.startupInterval = nil
        startupItemID = nil
        startupRequestToken = nil
    }
}

extension CMTime {
    fileprivate var secondsIfFinite: TimeInterval? {
        let value = seconds
        return value.isFinite && !value.isNaN && value >= 0 ? value : nil
    }
}
