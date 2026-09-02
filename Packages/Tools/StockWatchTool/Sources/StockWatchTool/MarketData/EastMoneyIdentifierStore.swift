import Foundation
import os

final class EastMoneyIdentifierStore: @unchecked Sendable {
    private static let key = "onebox.stockWatch.eastMoneyIdentifiers"

    private let defaults: UserDefaults?
    private let identifiers: OSAllocatedUnfairLock<[InstrumentID: String]>

    init(defaults: UserDefaults?) {
        self.defaults = defaults
        let stored = defaults?.dictionary(forKey: Self.key) as? [String: String] ?? [:]
        identifiers = OSAllocatedUnfairLock(
            initialState: Dictionary(
                uniqueKeysWithValues: stored.compactMap { rawID, identifier in
                    guard let instrumentID = try? InstrumentID(validatingRawValue: rawID) else {
                        return nil
                    }
                    return (instrumentID, identifier)
                }
            )
        )
    }

    func identifier(for instrumentID: InstrumentID) -> String? {
        identifiers.withLock { $0[instrumentID] }
    }

    func setIdentifier(_ identifier: String, for instrumentID: InstrumentID) {
        let stored = identifiers.withLock { identifiers in
            identifiers[instrumentID] = identifier
            return Dictionary(uniqueKeysWithValues: identifiers.map { ($0.key.rawValue, $0.value) })
        }
        defaults?.set(stored, forKey: Self.key)
    }

    func removeIdentifier(for instrumentID: InstrumentID) {
        let stored = identifiers.withLock { identifiers in
            identifiers.removeValue(forKey: instrumentID)
            return Dictionary(uniqueKeysWithValues: identifiers.map { ($0.key.rawValue, $0.value) })
        }
        defaults?.set(stored, forKey: Self.key)
    }
}
