import Foundation
import Observation
import OneBoxRuntime
import Synchronization

public struct DebugLogEntry: Identifiable, Sendable {
    public let id = UUID()
    public let moduleID: ToolID
    public let moduleName: String
    public let event: DiagnosticEvent

    public var timestampText: String { Self.copyDateFormat.string(from: event.timestamp) }
    public var localTimeText: String { Self.localTimeFormat.string(from: event.timestamp) }
    public var copyText: String {
        "[\(timestampText)] [\(moduleName)] \(event.operation)\n\(event.message)"
    }

    private static let copyDateFormat: DateFormatter = {
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.timeZone = TimeZone(secondsFromGMT: 0)
        format.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
        return format
    }()
    private static let localTimeFormat: DateFormatter = {
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.dateFormat = "HH:mm:ss.SSS"
        return format
    }()
}

@Observable
public final class DebugLogStore {
    public var isEnabled: Bool {
        didSet {
            guard oldValue != isEnabled else { return }
            captureSession.value.withLock { $0 = isEnabled ? UUID() : nil }
            if isEnabled { startedAt = Date() }
            onEnabledChanged(isEnabled)
        }
    }
    public private(set) var entries: [DebugLogEntry] = []
    public var selectedModuleID: ToolID?
    public private(set) var startedAt: Date?
    public private(set) var discardedCount = 0
    public let capacity: Int

    @ObservationIgnored private let captureSession: DebugCaptureState
    @ObservationIgnored private let onEnabledChanged: (Bool) -> Void

    public init(
        isEnabled: Bool = false,
        capacity: Int = 500,
        onEnabledChanged: @escaping (Bool) -> Void = { _ in }
    ) {
        self.isEnabled = isEnabled
        self.capacity = max(1, capacity)
        self.onEnabledChanged = onEnabledChanged
        captureSession = DebugCaptureState(session: isEnabled ? UUID() : nil)
        startedAt = isEnabled ? Date() : nil
    }

    public func diagnostics(for moduleID: ToolID, name: String) -> ToolDiagnostics {
        let captureSession = captureSession
        return ToolDiagnostics { [weak self] event in
            guard let session = captureSession.value.withLock({ $0 }) else { return }
            let sanitized = DiagnosticEvent(
                timestamp: event.timestamp,
                operation: Self.sanitize(event.operation),
                message: Self.sanitize(event.message)
            )
            Task { @MainActor [weak self] in
                guard let self, captureSession.value.withLock({ $0 }) == session else { return }
                entries.append(
                    DebugLogEntry(moduleID: moduleID, moduleName: name, event: sanitized))
                entries.sort { $0.event.timestamp < $1.event.timestamp }
                if entries.count > capacity {
                    discardedCount += entries.count - capacity
                    entries.removeFirst(entries.count - capacity)
                }
            }
        }
    }

    public func clear() {
        // Invalidate queued events too, so Clear cannot be undone by a pending actor hop.
        captureSession.value.withLock { $0 = isEnabled ? UUID() : nil }
        entries.removeAll()
        discardedCount = 0
        if isEnabled { startedAt = Date() }
    }

    public func filtered(moduleID: ToolID?, query: String) -> [DebugLogEntry] {
        entries.reversed().filter {
            (moduleID == nil || $0.moduleID == moduleID)
                && (query.isEmpty || $0.copyText.localizedStandardContains(query))
        }
    }

    nonisolated private static func sanitize(_ text: String) -> String {
        var result = text
        // Preserve source error wording/codes while omitting private local paths and URL credentials.
        let replacements = [
            (#"(?i)(https?://)[^\s/@]+:[^\s/@]+@"#, "$1<credentials>@"),
            (#"(https?://[^\s?\"<>]+)\?[^\s\"<>]*"#, "$1?<query>"),
            (#"(?:/private)?/var/folders/[^\s\"'<>]+"#, "<temporary-path>"),
            (#"/Users/[^\s\"'<>]+"#, "<user-path>"),
            (#"(?i)(authorization\s*[:=]\s*)(?:bearer|basic)\s+[^\s,;]+"#, "$1<redacted>"),
            (
                #"(?i)((?:access_token|refresh_token|api_key|password|cookie)\s*[:=]\s*)[^\s,;]+"#,
                "$1<redacted>"
            ),
        ]
        for (pattern, replacement) in replacements {
            result = result.replacingOccurrences(
                of: pattern, with: replacement, options: .regularExpression
            )
        }
        return result
    }
}

private nonisolated final class DebugCaptureState: Sendable {
    let value: Mutex<UUID?>

    init(session: UUID?) {
        value = Mutex(session)
    }
}
