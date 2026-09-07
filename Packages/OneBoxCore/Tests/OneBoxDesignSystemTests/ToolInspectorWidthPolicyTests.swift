import AppKit
import SwiftUI
import XCTest

@testable import OneBoxDesignSystem

final class ToolInspectorWidthPolicyTests: XCTestCase {
    @MainActor
    func testStandardInspectorUsesFixedDesignWidth() {
        XCTAssertEqual(ToolInspectorWidthPolicy.standard.minimum, DesignMetrics.inspectorWidth)
        XCTAssertEqual(ToolInspectorWidthPolicy.standard.ideal, DesignMetrics.inspectorWidth)
        XCTAssertEqual(ToolInspectorWidthPolicy.standard.maximum, DesignMetrics.inspectorWidth)
    }

    @MainActor
    func testQueueInspectorUsesFlexibleSupportedRange() {
        XCTAssertEqual(ToolInspectorWidthPolicy.queue.minimum, 280)
        XCTAssertEqual(ToolInspectorWidthPolicy.queue.ideal, 320)
        XCTAssertEqual(ToolInspectorWidthPolicy.queue.maximum, 360)
    }
}

@MainActor
final class ToolInspectorPresentationTests: XCTestCase {
    func testInitiallyPresentedInspectorInstallsAfterPrimaryViewWithoutRecreatingIt() throws {
        let model = InspectorPresentationModel(isPresented: true)
        let tracker = PrimaryViewTracker()
        let host = NSHostingView(
            rootView: InspectorPresentationHarness(
                model: model,
                tracker: tracker,
                widthPolicy: .standard
            )
        )
        host.frame = NSRect(x: 0, y: 0, width: 640, height: 480)
        let window = makeWindow(host: host)
        defer { detach(window) }

        settle(host)

        let primaryView = try XCTUnwrap(tracker.view)
        XCTAssertEqual(tracker.makeCount, 1)
        XCTAssertEqual(primaryView.frame.width, 392, accuracy: 1)

        model.isPresented = false
        settle(host)
        XCTAssertEqual(tracker.makeCount, 1)
        XCTAssertTrue(tracker.view === primaryView)
        XCTAssertEqual(primaryView.frame.width, 640, accuracy: 1)
    }

    func testOpeningAndClosingStandardInspectorPreservesPrimaryViewAndPushesContent() throws {
        let model = InspectorPresentationModel()
        let tracker = PrimaryViewTracker()
        let host = NSHostingView(
            rootView: InspectorPresentationHarness(
                model: model,
                tracker: tracker,
                widthPolicy: .standard
            )
        )
        host.frame = NSRect(x: 0, y: 0, width: 640, height: 480)
        let window = makeWindow(host: host)
        defer { detach(window) }

        settle(host)
        let primaryView = try XCTUnwrap(tracker.view)
        XCTAssertEqual(tracker.makeCount, 1)
        XCTAssertEqual(primaryView.frame.width, 640, accuracy: 1)

        model.isPresented = true
        settle(host)
        XCTAssertEqual(tracker.makeCount, 1)
        XCTAssertTrue(tracker.view === primaryView)
        XCTAssertEqual(primaryView.frame.width, 392, accuracy: 1)

        model.isPresented = false
        settle(host)
        XCTAssertEqual(tracker.makeCount, 1)
        XCTAssertTrue(tracker.view === primaryView)
        XCTAssertEqual(primaryView.frame.width, 640, accuracy: 1)
    }

    private func settle<Content: View>(_ host: NSHostingView<Content>) {
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        host.layoutSubtreeIfNeeded()
    }

    private func makeWindow<Content: View>(host: NSHostingView<Content>) -> NSWindow {
        let window = NSWindow(
            contentRect: host.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = host
        window.orderFrontRegardless()
        return window
    }

    private func detach(_ window: NSWindow) {
        window.orderOut(nil)
        window.contentView = nil
    }
}

@MainActor
private final class InspectorPresentationModel: ObservableObject {
    @Published var isPresented: Bool

    init(isPresented: Bool = false) {
        self.isPresented = isPresented
    }
}

@MainActor
private final class PrimaryViewTracker {
    var makeCount = 0
    weak var view: NSView?
}

@MainActor
private struct PrimaryViewProbe: NSViewRepresentable {
    let tracker: PrimaryViewTracker

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        tracker.makeCount += 1
        tracker.view = view
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

@MainActor
private struct InspectorPresentationHarness: View {
    @ObservedObject var model: InspectorPresentationModel
    let tracker: PrimaryViewTracker
    let widthPolicy: ToolInspectorWidthPolicy

    var body: some View {
        PrimaryViewProbe(tracker: tracker)
            .toolInspector(
                isPresented: $model.isPresented,
                title: "Inspector",
                closeLabel: "Close",
                widthPolicy: widthPolicy
            ) {
                Text("Inspector content")
            }
    }
}
