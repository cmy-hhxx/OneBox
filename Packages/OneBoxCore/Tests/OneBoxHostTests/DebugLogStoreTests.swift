import Foundation
import OneBoxRuntime
import Testing

@testable import OneBoxHost

@MainActor
@Suite("In-app diagnostics")
struct DebugLogStoreTests {
    @Test func copiedTimestampIncludesCalendarDateMillisecondsAndTimeZone() {
        let entry = DebugLogEntry(
            moduleID: ToolID(rawValue: "stock-watch"), moduleName: "股票看盘",
            event: DiagnosticEvent(
                timestamp: Date(timeIntervalSince1970: 1789293600.125),
                operation: "Refresh", message: "raw error"
            )
        )
        #expect(entry.copyText.hasPrefix("[2026-09-13T10:00:00.125Z] [股票看盘] Refresh\n"))
    }

    @Test func visibleAndCopiedTimeUseTheSameMillisecondRounding() {
        let entry = DebugLogEntry(
            moduleID: ToolID(rawValue: "stock-watch"), moduleName: "股票看盘",
            event: DiagnosticEvent(
                timestamp: Date(timeIntervalSince1970: 1789293600.1239),
                operation: "Refresh", message: "raw error")
        )
        #expect(entry.localTimeText.suffix(4) == entry.timestampText.dropLast().suffix(4))
    }

    @Test func captureRequiresOptInAndFiltersThreeModules() async throws {
        let store = DebugLogStore()
        let ascii = store.diagnostics(for: ToolID(rawValue: "ascii-art"), name: "ASCII 工坊")
        let stock = store.diagnostics(for: ToolID(rawValue: "stock-watch"), name: "股票看盘")
        let podpin = store.diagnostics(for: ToolID(rawValue: "podpin"), name: "PodPin")
        ascii.record(message: "before opt-in", operation: "Import")
        store.isEnabled = true
        ascii.record(message: "decode failed", operation: "Import")
        stock.record(message: "provider unavailable", operation: "Refresh")
        podpin.record(message: "media failed", operation: "Playback")
        try await waitUntil { store.entries.count == 3 }
        #expect(!store.entries.contains { $0.event.message == "before opt-in" })
        #expect(
            store.filtered(moduleID: ToolID(rawValue: "stock-watch"), query: "provider").count == 1)
        #expect(store.filtered(moduleID: nil, query: "Playback").count == 1)
        #expect(store.entries.allSatisfy { $0.copyText.contains($0.moduleName) })
    }

    @Test func clearingAndDisablingInvalidateAlreadyQueuedEvents() async throws {
        let store = DebugLogStore(isEnabled: true)
        let sink = store.diagnostics(for: ToolID(rawValue: "stock-watch"), name: "股票看盘")
        sink.record(message: "clear this pending event", operation: "Refresh")
        store.clear()
        sink.record(message: "disable this pending event", operation: "Refresh")
        store.isEnabled = false
        store.isEnabled = true
        sink.record(message: "current session", operation: "Refresh")
        try await waitUntil { store.entries.count == 1 }
        #expect(store.entries.first?.event.message == "current session")
    }

    @Test func boundedBufferPreservesRawCauseAndRedactsPrivateValues() async throws {
        let store = DebugLogStore(isEnabled: true, capacity: 2)
        let sink = store.diagnostics(for: ToolID(rawValue: "podpin"), name: "PodPin")
        sink.record(message: "old", operation: "Import")
        try await waitUntil { store.entries.count == 1 }
        sink.record(message: "middle", operation: "Import")
        try await waitUntil { store.entries.count == 2 }
        let cause = NSError(
            domain: "NSURLErrorDomain", code: -1001,
            userInfo: [
                NSLocalizedDescriptionKey: "The request timed out.",
                NSDebugDescriptionErrorKey:
                    "https://example.com/audio?token=secret /Users/alice/Music/private.mp3",
            ])
        let wrapper = NSError(
            domain: "Presentation", code: 1,
            userInfo: [
                NSLocalizedDescriptionKey: "Friendly failure", NSUnderlyingErrorKey: cause,
            ])
        sink.record(wrapper, operation: "Download")
        try await waitUntil { store.discardedCount == 1 }
        let entry = try #require(store.entries.last)
        #expect(store.entries.count == 2)
        #expect(entry.event.message.contains("NSURLErrorDomain (-1001)"))
        #expect(entry.event.message.contains("The request timed out."))
        #expect(!entry.event.message.contains("Friendly failure"))
        #expect(!entry.copyText.contains("secret"))
        #expect(!entry.copyText.contains("alice"))
        #expect(entry.copyText.contains("[PodPin] Download"))
        #expect(entry.copyText.contains("T"))
    }

    private func waitUntil(_ predicate: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !predicate(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(1))
        }
        #expect(predicate())
    }
}
