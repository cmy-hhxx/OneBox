import Foundation
import Observation

@MainActor
@Observable
final class StockWatchPreferences {
    var refreshInterval: Int {
        didSet {
            let sanitized = Self.sanitizedRefreshInterval(refreshInterval)
            if refreshInterval != sanitized {
                refreshInterval = sanitized
            }
            persist(sanitized, key: Keys.refreshInterval)
        }
    }

    var bullSoundEnabled: Bool {
        didSet { persist(bullSoundEnabled, key: Keys.bullSoundEnabled) }
    }

    var bearSoundEnabled: Bool {
        didSet { persist(bearSoundEnabled, key: Keys.bearSoundEnabled) }
    }

    @ObservationIgnored
    private let defaults: UserDefaults

    @ObservationIgnored
    private var isLoading = true

    init(
        defaults: UserDefaults = .standard,
        legacyDefaults: UserDefaults? = UserDefaults(
            suiteName: "io.github.cmy-hhxx.marketsprite"
        )
    ) {
        self.defaults = defaults
        refreshInterval = Self.loadRefreshInterval(
            defaults: defaults,
            legacyDefaults: legacyDefaults
        )
        bullSoundEnabled = Self.loadBoolean(
            defaults: defaults,
            legacyDefaults: legacyDefaults,
            key: Keys.bullSoundEnabled,
            legacyKey: LegacyKeys.bullSoundEnabled,
            fallback: true
        )
        bearSoundEnabled = Self.loadBoolean(
            defaults: defaults,
            legacyDefaults: legacyDefaults,
            key: Keys.bearSoundEnabled,
            legacyKey: LegacyKeys.bearSoundEnabled,
            fallback: true
        )
        isLoading = false
    }

    private func persist(_ value: Any, key: String) {
        guard !isLoading else { return }
        defaults.set(value, forKey: key)
    }

    private static func loadRefreshInterval(
        defaults: UserDefaults,
        legacyDefaults: UserDefaults?
    ) -> Int {
        if let stored = defaults.object(forKey: Keys.refreshInterval) {
            let value = sanitizedRefreshInterval(integer(from: stored) ?? 15)
            defaults.set(value, forKey: Keys.refreshInterval)
            return value
        }
        guard
            let legacyValue = legacyDefaults?.object(
                forKey: LegacyKeys.refreshInterval
            )
        else {
            return 15
        }
        let value = sanitizedRefreshInterval(integer(from: legacyValue) ?? 15)
        defaults.set(value, forKey: Keys.refreshInterval)
        return value
    }

    private static func loadBoolean(
        defaults: UserDefaults,
        legacyDefaults: UserDefaults?,
        key: String,
        legacyKey: String,
        fallback: Bool
    ) -> Bool {
        if let stored = defaults.object(forKey: key) {
            let value = boolean(from: stored) ?? fallback
            defaults.set(value, forKey: key)
            return value
        }
        guard let legacyValue = legacyDefaults?.object(forKey: legacyKey) else {
            return fallback
        }
        let value = boolean(from: legacyValue) ?? fallback
        defaults.set(value, forKey: key)
        return value
    }

    private static func integer(from value: Any) -> Int? {
        guard let number = value as? NSNumber,
            CFGetTypeID(number) != CFBooleanGetTypeID()
        else {
            return nil
        }
        let value = number.doubleValue
        guard value.isFinite,
            value.rounded() == value,
            value >= Double(Int.min),
            value <= Double(Int.max)
        else {
            return nil
        }
        return Int(value)
    }

    private static func boolean(from value: Any) -> Bool? {
        guard let number = value as? NSNumber,
            CFGetTypeID(number) == CFBooleanGetTypeID()
        else {
            return nil
        }
        return number.boolValue
    }

    private static func sanitizedRefreshInterval(_ value: Int) -> Int {
        [15, 30, 60].contains(value) ? value : 15
    }

    private enum Keys {
        static let refreshInterval = "onebox.stockWatch.refreshInterval"
        static let bullSoundEnabled = "onebox.stockWatch.bullSoundEnabled"
        static let bearSoundEnabled = "onebox.stockWatch.bearSoundEnabled"
    }

    private enum LegacyKeys {
        static let refreshInterval = "marketSprite.refreshInterval"
        static let bullSoundEnabled = "marketSprite.bullSoundEnabled"
        static let bearSoundEnabled = "marketSprite.bearSoundEnabled"
    }
}
