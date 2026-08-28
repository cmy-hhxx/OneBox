import Combine
import Foundation

/// Lightweight app chrome preferences. Library and playback state stay in the
/// database; this object deliberately owns only persistent presentation state.
@MainActor
final class AppPreferences: ObservableObject {
    static let supportedPlaybackRates: [Double] = [0.75, 1, 1.25, 1.5, 2]
    nonisolated static let nowPlayingContentOpacityRange = 0.45...1.0
    nonisolated static let playbackVolumeRange = 0.0...1.0

    @Published var nowPlayingContentOpacity: Double {
        didSet {
            let normalized = Self.clamped(
                nowPlayingContentOpacity, to: Self.nowPlayingContentOpacityRange)
            guard normalized == nowPlayingContentOpacity else {
                nowPlayingContentOpacity = normalized
                return
            }
            persist(normalized, key: Keys.nowPlayingContentOpacity)
        }
    }

    @Published var playbackRate: Double {
        didSet {
            let normalized = Self.closestSupportedPlaybackRate(to: playbackRate)
            guard normalized == playbackRate else {
                playbackRate = normalized
                return
            }
            persist(normalized, key: Keys.playbackRate)
        }
    }

    @Published var playbackVolume: Double {
        didSet {
            let normalized = Self.clamped(playbackVolume, to: Self.playbackVolumeRange)
            guard normalized == playbackVolume else {
                playbackVolume = normalized
                return
            }
            persist(normalized, key: Keys.playbackVolume)
        }
    }

    @Published var lastLibraryCollection: LibraryCollection {
        didSet { persistLibraryCollection(lastLibraryCollection) }
    }

    private let defaults: UserDefaults
    private var isLoading = true

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        nowPlayingContentOpacity = Self.clamped(
            Self.double(defaults, key: Keys.nowPlayingContentOpacity, fallback: 1),
            to: Self.nowPlayingContentOpacityRange
        )
        playbackRate = Self.closestSupportedPlaybackRate(
            to: Self.double(defaults, key: Keys.playbackRate, fallback: 1))
        playbackVolume = Self.clamped(
            Self.double(defaults, key: Keys.playbackVolume, fallback: 1),
            to: Self.playbackVolumeRange
        )
        lastLibraryCollection = Self.libraryCollection(from: defaults) ?? .recentlyImported
        isLoading = false
    }

    static func nextPlaybackRate(after rate: Double) -> Double {
        guard let currentIndex = supportedPlaybackRates.firstIndex(of: rate) else { return 1 }
        let nextIndex = supportedPlaybackRates.index(after: currentIndex)
        return nextIndex == supportedPlaybackRates.endIndex
            ? supportedPlaybackRates[0] : supportedPlaybackRates[nextIndex]
    }

    private func persistLibraryCollection(_ collection: LibraryCollection) {
        guard !isLoading else { return }
        guard let data = try? JSONEncoder().encode(collection) else { return }
        defaults.set(data, forKey: Keys.lastLibraryCollection)
    }

    private func persist(_ value: Any, key: String) {
        guard !isLoading else { return }
        defaults.set(value, forKey: key)
    }

    private static func double(_ defaults: UserDefaults, key: String, fallback: Double) -> Double {
        (defaults.object(forKey: key) as? NSNumber)?.doubleValue ?? fallback
    }

    private static func libraryCollection(from defaults: UserDefaults) -> LibraryCollection? {
        guard let data = defaults.data(forKey: Keys.lastLibraryCollection) else { return nil }
        return try? JSONDecoder().decode(LibraryCollection.self, from: data)
    }

    private static func closestSupportedPlaybackRate(to rate: Double) -> Double {
        guard rate.isFinite else { return 1 }
        return supportedPlaybackRates.min { abs($0 - rate) < abs($1 - rate) } ?? 1
    }

    private static func clamped(_ value: Double, to range: ClosedRange<Double>) -> Double {
        guard value.isFinite else { return range.upperBound }
        return min(max(value, range.lowerBound), range.upperBound)
    }

    private enum Keys {
        static let nowPlayingContentOpacity = "podpin.nowPlayingContentOpacity"
        static let playbackRate = "podpin.playbackRate"
        static let playbackVolume = "podpin.playbackVolume"
        static let lastLibraryCollection = "podpin.lastLibraryCollection"
    }
}
