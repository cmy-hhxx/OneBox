import Combine
import Foundation

/// The lightweight state consumed by surfaces that need live playback updates.
/// Keeping it outside `PodPinStore` prevents the library and settings trees from
/// being invalidated by the player's half-second time observer.
@MainActor
struct PlaybackSnapshot: Equatable {
    var item: AudioItem?
    var phase: PlaybackPhase
    var currentTime: TimeInterval
    var duration: TimeInterval
    var listeningHistory: ListeningHistory = ListeningHistory()
    var rate: Double
    var artworkURL: URL? = nil

    static let empty = PlaybackSnapshot(
        item: nil,
        phase: .idle,
        currentTime: 0,
        duration: 0,
        listeningHistory: ListeningHistory(),
        rate: 1,
        artworkURL: nil
    )

    var isPlayable: Bool {
        item != nil
    }

    var isPlaying: Bool {
        phase == .playing
    }
}

@MainActor
struct PlaybackIdentitySnapshot: Equatable {
    var item: AudioItem?
    var phase: PlaybackPhase
    var rate: Double
    var artworkURL: URL?

    static let empty = PlaybackIdentitySnapshot(
        item: nil,
        phase: .idle,
        rate: 1,
        artworkURL: nil
    )

    init(item: AudioItem?, phase: PlaybackPhase, rate: Double, artworkURL: URL?) {
        self.item = item
        self.phase = phase
        self.rate = rate
        self.artworkURL = artworkURL
    }

    init(snapshot: PlaybackSnapshot) {
        item = snapshot.item
        phase = snapshot.phase
        rate = snapshot.rate
        artworkURL = snapshot.artworkURL
    }

    var isPlayable: Bool { item != nil }
    var isPlaying: Bool { phase == .playing }
}

@MainActor
struct PlaybackTimelineSnapshot: Equatable {
    var currentTime: TimeInterval
    var duration: TimeInterval
    var listeningHistory: ListeningHistory

    static let empty = PlaybackTimelineSnapshot(
        currentTime: 0,
        duration: 0,
        listeningHistory: ListeningHistory()
    )

    init(
        currentTime: TimeInterval,
        duration: TimeInterval,
        listeningHistory: ListeningHistory = ListeningHistory()
    ) {
        self.currentTime = currentTime
        self.duration = duration
        self.listeningHistory = listeningHistory
    }

    init(snapshot: PlaybackSnapshot) {
        currentTime = snapshot.currentTime
        duration = snapshot.duration
        listeningHistory = snapshot.listeningHistory
    }
}

@MainActor
struct PlaybackOutputSnapshot: Equatable {
    var volume: Double
    var routeRevision: Int

    static let `default` = PlaybackOutputSnapshot(volume: 1, routeRevision: 0)
}

@MainActor
final class PlaybackIdentitySession: ObservableObject {
    @Published private(set) var snapshot: PlaybackIdentitySnapshot = .empty

    func update(_ snapshot: PlaybackIdentitySnapshot) {
        guard self.snapshot != snapshot else { return }
        self.snapshot = snapshot
    }
}

@MainActor
final class PlaybackTimelineSession: ObservableObject {
    @Published private(set) var snapshot: PlaybackTimelineSnapshot = .empty

    func update(_ snapshot: PlaybackTimelineSnapshot) {
        guard self.snapshot != snapshot else { return }
        self.snapshot = snapshot
    }
}

/// Keeps high-frequency volume drags isolated from the player identity and
/// timeline trees. Output controls are the only SwiftUI subtree that observes
/// this session.
@MainActor
final class PlaybackOutputSession: ObservableObject {
    @Published private(set) var snapshot: PlaybackOutputSnapshot = .default

    func update(_ snapshot: PlaybackOutputSnapshot) {
        guard self.snapshot != snapshot else { return }
        self.snapshot = snapshot
    }
}

/// Separates infrequent identity changes from the half-second timeline tick so
/// the latter can be observed only by scrubbers and time labels.
@MainActor
final class PlaybackPresentationModel {
    let identity = PlaybackIdentitySession()
    let timeline = PlaybackTimelineSession()
    let output = PlaybackOutputSession()

    var snapshot: PlaybackSnapshot {
        PlaybackSnapshot(
            item: identity.snapshot.item,
            phase: identity.snapshot.phase,
            currentTime: timeline.snapshot.currentTime,
            duration: timeline.snapshot.duration,
            listeningHistory: timeline.snapshot.listeningHistory,
            rate: identity.snapshot.rate,
            artworkURL: identity.snapshot.artworkURL
        )
    }

    func update(
        _ snapshot: PlaybackSnapshot,
        outputVolume: Double? = nil,
        outputRevision: Int? = nil
    ) {
        identity.update(PlaybackIdentitySnapshot(snapshot: snapshot))
        timeline.update(PlaybackTimelineSnapshot(snapshot: snapshot))
        if outputVolume != nil || outputRevision != nil {
            output.update(
                PlaybackOutputSnapshot(
                    volume: outputVolume ?? output.snapshot.volume,
                    routeRevision: outputRevision ?? output.snapshot.routeRevision
                )
            )
        }
    }
}
