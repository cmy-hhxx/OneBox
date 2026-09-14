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
    func testAnimationDoesNotProbeWorkspaceAtZeroOrUnboundedWidths() throws {
        let model = InspectorPresentationModel()
        let tracker = PrimaryViewTracker()
        let host = NSHostingView(
            rootView: InspectorPresentationHarness(
                model: model, tracker: tracker, widthPolicy: .standard))
        host.frame = NSRect(x: 0, y: 0, width: 640, height: 480)
        let window = makeWindow(host: host)
        defer { detach(window) }
        settle(host)
        tracker.proposedWidths = []
        model.isPresented = true
        _ = sampleWidths(host, tracker: tracker, duration: 0.4)
        XCTAssertFalse(tracker.proposedWidths.isEmpty)
        XCTAssertTrue(
            tracker.proposedWidths.allSatisfy { $0.isFinite && $0 >= 379 && $0 <= 641 },
            "Only actual workspace widths should be measured: \(tracker.proposedWidths)")
    }

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
        XCTAssertEqual(primaryView.frame.width, 380, accuracy: 1)

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
        XCTAssertEqual(primaryView.frame.width, 380, accuracy: 1)

        model.isPresented = false
        settle(host)
        XCTAssertEqual(tracker.makeCount, 1)
        XCTAssertTrue(tracker.view === primaryView)
        XCTAssertEqual(primaryView.frame.width, 640, accuracy: 1)
    }

    func testFirstOpeningResizesThroughIntermediateFrames() throws {
        let model = InspectorPresentationModel()
        let tracker = PrimaryViewTracker()
        let host = NSHostingView(
            rootView: InspectorPresentationHarness(
                model: model, tracker: tracker, widthPolicy: .standard))
        host.frame = NSRect(x: 0, y: 0, width: 640, height: 480)
        let window = makeWindow(host: host)
        defer { detach(window) }
        settle(host)
        let original = try XCTUnwrap(tracker.view)
        model.isPresented = true
        let widths = sampleWidths(host, tracker: tracker, duration: 0.5)
        let end = try XCTUnwrap(widths.last)
        XCTAssertLessThan(end, 420)
        XCTAssertTrue(
            widths.contains { $0 > end + 8 && $0 < 632 },
            "Opening must resize continuously, got: \(widths)")
        XCTAssertTrue(tracker.view === original)
        XCTAssertEqual(tracker.makeCount, 1)
    }

    func testOpeningCanReverseBeforeTheTransitionCompletes() throws {
        let model = InspectorPresentationModel()
        let tracker = PrimaryViewTracker()
        let host = NSHostingView(
            rootView: InspectorPresentationHarness(
                model: model, tracker: tracker, widthPolicy: .standard))
        host.frame = NSRect(x: 0, y: 0, width: 640, height: 480)
        let window = makeWindow(host: host)
        defer { detach(window) }
        settle(host)
        model.isPresented = true
        _ = sampleWidths(host, tracker: tracker, duration: 0.06)
        model.isPresented = false
        let widths = sampleWidths(host, tracker: tracker, duration: 0.5)
        XCTAssertEqual(try XCTUnwrap(widths.last), 640, accuracy: 1)
        XCTAssertFalse(model.isPresented)
        XCTAssertEqual(tracker.makeCount, 1)
    }

    func testReducedMotionSkipsIntermediateLayoutFrames() throws {
        let model = InspectorPresentationModel(reduceMotion: true)
        let tracker = PrimaryViewTracker()
        let host = NSHostingView(
            rootView: InspectorPresentationHarness(
                model: model, tracker: tracker, widthPolicy: .standard))
        host.frame = NSRect(x: 0, y: 0, width: 640, height: 480)
        let window = makeWindow(host: host)
        defer { detach(window) }
        settle(host)
        model.isPresented = true
        let widths = sampleWidths(host, tracker: tracker, duration: 0.15)
        XCTAssertEqual(try XCTUnwrap(widths.last), 380, accuracy: 1)
        XCTAssertTrue(
            widths.allSatisfy { abs($0 - 640) < 1 || abs($0 - 380) < 1 },
            "Reduced Motion must not interpolate widths: \(widths)")
        XCTAssertEqual(tracker.makeCount, 1)
    }

    func testQueueWidthPolicyAndRepeatedReversalPreservePrimaryIdentity() throws {
        let model = InspectorPresentationModel()
        let tracker = PrimaryViewTracker()
        let host = NSHostingView(
            rootView: InspectorPresentationHarness(
                model: model, tracker: tracker, widthPolicy: .queue))
        host.frame = NSRect(x: 0, y: 0, width: 720, height: 480)
        let window = makeWindow(host: host)
        defer { detach(window) }
        settle(host)
        let original = try XCTUnwrap(tracker.view)
        for target in [true, false, true, false] {
            model.isPresented = target
            _ = sampleWidths(host, tracker: tracker, duration: 0.05)
        }
        var widths = sampleWidths(host, tracker: tracker, duration: 0.4)
        XCTAssertEqual(try XCTUnwrap(widths.last), 720, accuracy: 1)
        for target in [true, false, true] {
            model.isPresented = target
            _ = sampleWidths(host, tracker: tracker, duration: 0.05)
        }
        widths = sampleWidths(host, tracker: tracker, duration: 0.5)
        XCTAssertTrue(model.isPresented)
        let width = try XCTUnwrap(widths.last)
        XCTAssertGreaterThanOrEqual(width, 720 - 360 - DesignMetrics.inspectorGutter - 1)
        XCTAssertLessThanOrEqual(width, 720 - 280 - DesignMetrics.inspectorGutter + 1)
        XCTAssertTrue(tracker.view === original)
        XCTAssertEqual(tracker.makeCount, 1)
    }

    private func sampleWidths<Content: View>(
        _ host: NSHostingView<Content>, tracker: PrimaryViewTracker, duration: TimeInterval
    ) -> [CGFloat] {
        let deadline = Date().addingTimeInterval(duration)
        var samples: [CGFloat] = []
        repeat {
            RunLoop.main.run(until: min(deadline, Date().addingTimeInterval(0.01)))
            host.layoutSubtreeIfNeeded()
            if let view = tracker.view { samples.append(view.frame.width) }
        } while Date() < deadline
        return samples
    }

    private func settle<Content: View>(_ host: NSHostingView<Content>) {
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
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
    let reduceMotion: Bool

    init(isPresented: Bool = false, reduceMotion: Bool = false) {
        self.isPresented = isPresented
        self.reduceMotion = reduceMotion
    }
}

@MainActor
private final class PrimaryViewTracker {
    var makeCount = 0
    weak var view: NSView?
    var proposedWidths: [CGFloat] = []
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

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSView, context: Context) -> CGSize? {
        tracker.proposedWidths.append(proposal.width ?? .infinity)
        return nil
    }
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
            .environment(\.oneBoxAccessibilityReduceMotionOverride, model.reduceMotion)
    }
}
