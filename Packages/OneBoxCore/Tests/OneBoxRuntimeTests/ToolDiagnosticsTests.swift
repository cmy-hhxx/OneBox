import Foundation
import Synchronization
import Testing

@testable import OneBoxRuntime

@Suite("Diagnostic error reporting")
struct ToolDiagnosticsTests {
    @Test func nativeErrorDoesNotRepeatItsDescriptionAsAReflectionDump() {
        let events = DiagnosticEventBuffer()
        let sink = ToolDiagnostics { event in events.values.withLock { $0.append(event) } }
        sink.record(
            NSError(
                domain: "NSURLErrorDomain", code: -1001,
                userInfo: [NSLocalizedDescriptionKey: "The request timed out."]),
            operation: "Fetch quote"
        )
        #expect(
            events.values.withLock { $0.first?.message }
                == "NSURLErrorDomain (-1001)\nThe request timed out.")
    }

    @Test func cancellationIsNotAnErrorLog() {
        let events = DiagnosticEventBuffer()
        let sink = ToolDiagnostics { event in events.values.withLock { $0.append(event) } }
        sink.record(CancellationError(), operation: "Cancel")
        sink.record(URLError(.cancelled), operation: "Cancel request")
        sink.record(CocoaError(.userCancelled), operation: "Cancel dialog")
        #expect(events.values.withLock { $0.isEmpty })
    }

    @Test func underlyingErrorRetainsOriginalDomainCodeAndReason() {
        let events = DiagnosticEventBuffer()
        let sink = ToolDiagnostics { event in events.values.withLock { $0.append(event) } }
        let original = NSError(
            domain: "Provider", code: 503,
            userInfo: [
                NSLocalizedDescriptionKey: "Service unavailable",
                NSLocalizedFailureReasonErrorKey: "upstream timeout",
            ])
        let wrapper = NSError(domain: "UI", code: 1, userInfo: [NSUnderlyingErrorKey: original])
        sink.record(wrapper, operation: "Fetch quote")
        let event = events.values.withLock { $0.first }
        #expect(event?.message == "Provider (503)\nService unavailable\nupstream timeout")
        #expect(event?.operation == "Fetch quote")
    }
}

private final class DiagnosticEventBuffer: Sendable {
    let values = Mutex<[DiagnosticEvent]>([])
}
