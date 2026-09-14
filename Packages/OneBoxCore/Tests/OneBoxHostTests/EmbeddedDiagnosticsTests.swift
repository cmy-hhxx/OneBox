import AppKit
import OneBoxRuntime
import SwiftUI
import XCTest

@testable import OneBoxHost

@MainActor
final class EmbeddedDiagnosticsTests: XCTestCase {
    func testOpeningAndClosingLogsPreservesTheMountedToolInTheSameWindow() async throws {
        let model = LogPanelModel()
        let tracker = MountedToolTracker()
        let store = DebugLogStore(isEnabled: true)
        let toolID = ToolID(rawValue: "podpin")
        let catalog = ToolCatalog(registrations: [
            ToolRegistration(id: toolID, displayName: "PodPin") {
                MountedToolProbe(tracker: tracker)
                    .onAppear { tracker.appearances += 1 }
                    .onDisappear { tracker.disappearances += 1 }
            }
        ])
        let host = NSHostingView(
            rootView: LogPanelHarness(model: model, store: store, catalog: catalog))
        host.frame = NSRect(x: 0, y: 0, width: 1048, height: 648)
        let window = NSWindow(
            contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host
        window.orderFrontRegardless()
        defer {
            window.orderOut(nil)
            window.contentView = nil
        }
        try await Task.sleep(for: .milliseconds(80))
        let original = try XCTUnwrap(tracker.view)
        let windowNumbers = Set(NSApp.windows.filter(\.isVisible).map(\.windowNumber))

        // Exercise the same environment action used by tool error banners.
        store.selectedModuleID = ToolID(rawValue: "stock-watch")
        try XCTUnwrap(tracker.openDiagnostics)()
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertTrue(model.isPresented)
        XCTAssertEqual(store.selectedModuleID, toolID)
        store.diagnostics(for: toolID, name: "PodPin").record(
            NSError(domain: "OriginalFixture", code: 17), operation: "download")
        for _ in 0..<30 where store.entries.isEmpty { await Task.yield() }
        XCTAssertEqual(store.entries.count, 1)

        for isPresented in [false, true, false] {
            model.isPresented = isPresented
            try await Task.sleep(for: .milliseconds(60))
            host.layoutSubtreeIfNeeded()
            XCTAssertTrue(tracker.view === original)
            XCTAssertTrue(original.window === window)
            XCTAssertGreaterThan(original.frame.height, 0)
            XCTAssertEqual(tracker.makeCount, 1)
            XCTAssertEqual(tracker.appearances, 1)
            XCTAssertEqual(tracker.disappearances, 0)
            XCTAssertEqual(
                Set(NSApp.windows.filter(\.isVisible).map(\.windowNumber)), windowNumbers)
        }
    }
}

@MainActor
private final class LogPanelModel: ObservableObject {
    @Published var isPresented = false
}

@MainActor
private final class MountedToolTracker {
    weak var view: NSView?
    var makeCount = 0
    var appearances = 0
    var disappearances = 0
    var openDiagnostics: (() -> Void)?
}

@MainActor
private struct MountedToolProbe: NSViewRepresentable {
    let tracker: MountedToolTracker
    @Environment(\.openToolDiagnostics) private var openDiagnostics

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        tracker.makeCount += 1
        tracker.view = view
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        tracker.openDiagnostics = { openDiagnostics() }
    }
}

@MainActor
private struct LogPanelHarness: View {
    @ObservedObject var model: LogPanelModel
    let store: DebugLogStore
    let catalog: ToolCatalog

    var body: some View {
        HostView(
            catalog: catalog, debugLogStore: store,
            isDiagnosticsPresented: $model.isPresented)
    }
}
