import Foundation

enum InstrumentValidationError: LocalizedError, Equatable, Sendable {
    case emptyName
    case nameTooLong
    case invalidNameCharacter
    case invalidSymbol(namespace: SymbolNamespace, value: String)
    case malformedID(String)

    var errorDescription: String? {
        switch self {
        case .emptyName:
            tr("标的名称不能为空")
        case .nameTooLong:
            tr("标的名称不能超过 128 个字符")
        case .invalidNameCharacter:
            tr("标的名称不能包含控制字符或冒号")
        case .invalidSymbol(let namespace, let value):
            String(
                format: tr("%@ 的标的代码格式无效：%@"),
                namespace.displayName,
                value
            )
        case .malformedID(let value):
            String(format: tr("标的 ID 格式无效：%@"), value)
        }
    }
}

struct InstrumentID: RawRepresentable, Codable, Hashable, Sendable, CustomStringConvertible {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    init(namespace: SymbolNamespace, symbol: String) {
        self.rawValue = "\(namespace.rawValue):\(namespace.normalize(symbol: symbol))"
    }

    init(validatingRawValue rawValue: String) throws {
        let parts = rawValue.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2,
            let namespace = SymbolNamespace(rawValue: String(parts[0]))
        else {
            throw InstrumentValidationError.malformedID(rawValue)
        }
        let symbol = try Instrument.validatedSymbol(
            String(parts[1]),
            namespace: namespace
        )
        let canonical = "\(namespace.rawValue):\(symbol)"
        guard canonical == rawValue else {
            throw InstrumentValidationError.malformedID(rawValue)
        }
        self.rawValue = canonical
    }

    var description: String { rawValue }
}

struct Instrument: Identifiable, Hashable, Sendable {
    let id: InstrumentID
    let symbol: String
    let name: String
    let namespace: SymbolNamespace

    var market: Market { namespace.market }

    init(symbol: String, name: String, namespace: SymbolNamespace) {
        do {
            try self.init(validatingSymbol: symbol, name: name, namespace: namespace)
        } catch {
            preconditionFailure("Invalid trusted instrument: \(error.localizedDescription)")
        }
    }

    init(validatingSymbol symbol: String, name: String, namespace: SymbolNamespace) throws {
        let normalizedSymbol = try Self.validatedSymbol(symbol, namespace: namespace)
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty else {
            throw InstrumentValidationError.emptyName
        }
        guard normalizedName.count <= 128 else {
            throw InstrumentValidationError.nameTooLong
        }
        guard
            !normalizedName.unicodeScalars.contains(where: {
                CharacterSet.controlCharacters.contains($0) || $0 == ":"
            })
        else {
            throw InstrumentValidationError.invalidNameCharacter
        }
        self.id = InstrumentID(namespace: namespace, symbol: normalizedSymbol)
        self.symbol = normalizedSymbol
        self.name = normalizedName
        self.namespace = namespace
    }

    fileprivate static func validatedSymbol(
        _ symbol: String,
        namespace: SymbolNamespace
    ) throws -> String {
        let normalized = namespace.normalize(symbol: symbol)
        let scalars = normalized.unicodeScalars
        let isASCIIInteger =
            !scalars.isEmpty
            && scalars.allSatisfy {
                $0.value >= 48 && $0.value <= 57
            }
        let isValid: Bool
        let canonical: String
        switch namespace {
        case .shanghai, .shenzhen, .beijing:
            isValid = normalized.count == 6 && isASCIIInteger
            canonical = normalized
        case .hongKong:
            isValid = (1...5).contains(normalized.count) && isASCIIInteger
            canonical =
                String(repeating: "0", count: max(0, 5 - normalized.count))
                + normalized
        case .unitedStates:
            let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-")
            isValid =
                (1...16).contains(normalized.count)
                && scalars.allSatisfy { allowed.contains($0) }
            canonical = normalized
        }
        guard isValid else {
            throw InstrumentValidationError.invalidSymbol(
                namespace: namespace,
                value: symbol
            )
        }
        return canonical
    }

    static let initialWatchlist: [Instrument] = [
        Instrument(symbol: "600519", name: "贵州茅台", namespace: .shanghai),
        Instrument(symbol: "00700", name: "腾讯控股", namespace: .hongKong),
        Instrument(symbol: "AAPL", name: "苹果", namespace: .unitedStates),
    ]
}

extension Instrument: Codable {
    private enum CodingKeys: String, CodingKey {
        case symbol
        case name
        case namespace
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            validatingSymbol: try container.decode(String.self, forKey: .symbol),
            name: try container.decode(String.self, forKey: .name),
            namespace: try container.decode(SymbolNamespace.self, forKey: .namespace)
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(symbol, forKey: .symbol)
        try container.encode(name, forKey: .name)
        try container.encode(namespace, forKey: .namespace)
    }
}
