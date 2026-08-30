import XCTest

@testable import StockWatchTool

@MainActor
final class StockWatchPreferencesTests: XCTestCase {
    func testOnlyEmbeddedPreferencesRoundTripUnderStockWatchPrefix() {
        let domains = makeDomains()
        defer { domains.remove() }
        let preferences = StockWatchPreferences(
            defaults: domains.defaults,
            legacyDefaults: domains.legacyDefaults
        )

        preferences.refreshInterval = 30
        preferences.bullSoundEnabled = false
        preferences.bearSoundEnabled = false

        let storedKeys = Set(
            domains.defaults.persistentDomain(forName: domains.suiteName)?.keys.map { $0 } ?? []
        )
        XCTAssertEqual(
            storedKeys,
            [
                "onebox.stockWatch.refreshInterval",
                "onebox.stockWatch.bullSoundEnabled",
                "onebox.stockWatch.bearSoundEnabled",
            ]
        )

        let reloaded = StockWatchPreferences(
            defaults: domains.defaults,
            legacyDefaults: domains.legacyDefaults
        )
        XCTAssertEqual(reloaded.refreshInterval, 30)
        XCTAssertFalse(reloaded.bullSoundEnabled)
        XCTAssertFalse(reloaded.bearSoundEnabled)
    }

    func testInvalidStoredAndAssignedValuesAreSanitized() {
        let domains = makeDomains()
        defer { domains.remove() }
        domains.defaults.set("fast", forKey: "onebox.stockWatch.refreshInterval")
        domains.defaults.set(1, forKey: "onebox.stockWatch.bullSoundEnabled")
        domains.defaults.set("yes", forKey: "onebox.stockWatch.bearSoundEnabled")

        let preferences = StockWatchPreferences(
            defaults: domains.defaults,
            legacyDefaults: domains.legacyDefaults
        )

        XCTAssertEqual(preferences.refreshInterval, 15)
        XCTAssertTrue(preferences.bullSoundEnabled)
        XCTAssertTrue(preferences.bearSoundEnabled)
        XCTAssertEqual(
            domains.defaults.integer(forKey: "onebox.stockWatch.refreshInterval"),
            15
        )
        XCTAssertEqual(
            domains.defaults.object(forKey: "onebox.stockWatch.bullSoundEnabled") as? Bool,
            true
        )
        XCTAssertEqual(
            domains.defaults.object(forKey: "onebox.stockWatch.bearSoundEnabled") as? Bool,
            true
        )

        preferences.refreshInterval = 31
        XCTAssertEqual(preferences.refreshInterval, 15)
        XCTAssertEqual(
            domains.defaults.integer(forKey: "onebox.stockWatch.refreshInterval"),
            15
        )
    }

    func testLegacyStandaloneValuesAreImportedOnlyWhenNewKeysAreAbsent() {
        let domains = makeDomains()
        defer { domains.remove() }
        domains.legacyDefaults.set(60, forKey: "marketSprite.refreshInterval")
        domains.legacyDefaults.set(false, forKey: "marketSprite.bullSoundEnabled")
        domains.legacyDefaults.set(false, forKey: "marketSprite.bearSoundEnabled")

        let imported = StockWatchPreferences(
            defaults: domains.defaults,
            legacyDefaults: domains.legacyDefaults
        )
        XCTAssertEqual(imported.refreshInterval, 60)
        XCTAssertFalse(imported.bullSoundEnabled)
        XCTAssertFalse(imported.bearSoundEnabled)

        domains.legacyDefaults.set(15, forKey: "marketSprite.refreshInterval")
        domains.legacyDefaults.set(true, forKey: "marketSprite.bullSoundEnabled")
        let reloaded = StockWatchPreferences(
            defaults: domains.defaults,
            legacyDefaults: domains.legacyDefaults
        )
        XCTAssertEqual(reloaded.refreshInterval, 60)
        XCTAssertFalse(reloaded.bullSoundEnabled)
    }

    func testInvalidLegacyValuesImportSanitizedDefaults() {
        let domains = makeDomains()
        defer { domains.remove() }
        domains.legacyDefaults.set(5, forKey: "marketSprite.refreshInterval")
        domains.legacyDefaults.set("no", forKey: "marketSprite.bullSoundEnabled")
        domains.legacyDefaults.set(0, forKey: "marketSprite.bearSoundEnabled")

        let preferences = StockWatchPreferences(
            defaults: domains.defaults,
            legacyDefaults: domains.legacyDefaults
        )

        XCTAssertEqual(preferences.refreshInterval, 15)
        XCTAssertTrue(preferences.bullSoundEnabled)
        XCTAssertTrue(preferences.bearSoundEnabled)
        XCTAssertEqual(
            domains.defaults.integer(forKey: "onebox.stockWatch.refreshInterval"),
            15
        )
    }

    private func makeDomains() -> PreferenceDomains {
        let suiteName = "StockWatchPreferencesTests.\(UUID().uuidString)"
        let legacySuiteName = "StockWatchPreferencesLegacyTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let legacyDefaults = UserDefaults(suiteName: legacySuiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        legacyDefaults.removePersistentDomain(forName: legacySuiteName)
        return PreferenceDomains(
            suiteName: suiteName,
            legacySuiteName: legacySuiteName,
            defaults: defaults,
            legacyDefaults: legacyDefaults
        )
    }
}

private struct PreferenceDomains {
    let suiteName: String
    let legacySuiteName: String
    let defaults: UserDefaults
    let legacyDefaults: UserDefaults

    func remove() {
        defaults.removePersistentDomain(forName: suiteName)
        legacyDefaults.removePersistentDomain(forName: legacySuiteName)
    }
}
