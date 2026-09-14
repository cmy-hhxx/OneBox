import AppKit
import OneBoxDesignSystem
import OneBoxRuntime
import SwiftUI
import XCTest

@testable import OneBoxHost

@MainActor
final class SidebarLayoutTests: XCTestCase {
    func testExplicitContentWidthDoesNotLockWindowToItsCurrentSize() async throws {
        let recorder = ContentWidthRecorder()
        let host = NSHostingView(
            rootView: HostView(
                catalog: ToolCatalog(registrations: [
                    ToolRegistration(id: ToolID(rawValue: "resize"), displayName: "Resize") {
                        ContentWidthProbe(recorder: recorder)
                    }
                ])))
        host.frame = NSRect(x: 0, y: 0, width: 1048, height: 648)
        let window = NSWindow(
            contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host
        window.orderFrontRegardless()
        defer {
            window.orderOut(nil)
            window.contentView = nil
        }
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertLessThanOrEqual(host.fittingSize.width, DesignMetrics.minimumWindowSize.width)
        window.setContentSize(CGSize(width: 948, height: 556))
        try await Task.sleep(for: .milliseconds(50))
        host.layoutSubtreeIfNeeded()
        XCTAssertEqual(try XCTUnwrap(recorder.view).frame.width, 664, accuracy: 1)
    }

    func testHostProposesOnlyTheAvailableWidthToToolContent() async throws {
        let recorder = ContentWidthRecorder()
        let catalog = ToolCatalog(registrations: [
            ToolRegistration(id: ToolID(rawValue: "sizing"), displayName: "Sizing") {
                ContentWidthProbe(recorder: recorder)
            }
        ])
        let host = NSHostingView(rootView: HostView(catalog: catalog))
        host.frame = NSRect(x: 0, y: 0, width: 1048, height: 648)
        let window = NSWindow(
            contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host
        window.orderFrontRegardless()
        defer {
            window.orderOut(nil)
            window.contentView = nil
        }
        // Native split panes begin at zero before attachment. Measure resizing of
        // the mounted workspace, where repeated zero/infinite probes cause hitches.
        try await Task.sleep(for: .milliseconds(80))
        for width: CGFloat in [948, 1248, 1048] {
            recorder.widths = []
            window.setContentSize(CGSize(width: width, height: 648))
            try await Task.sleep(for: .milliseconds(50))
            host.layoutSubtreeIfNeeded()
            XCTAssertFalse(recorder.widths.isEmpty)
            XCTAssertTrue(
                recorder.widths.allSatisfy { $0.isFinite && $0 > 300 },
                "Sidebar layout must not probe the entire tool at zero/infinite width: \(recorder.widths)"
            )
        }
    }

    func testSelectionStaysOnSameBaselineAcrossRailWidths() async throws {
        let catalog = ToolCatalog(registrations: [
            ToolRegistration(
                id: ToolID(rawValue: "ascii-art"), displayName: "ASCII 工坊",
                systemImage: "character.textbox"
            ) { Text("ASCII") },
            ToolRegistration(
                id: ToolID(rawValue: "stock-watch"), displayName: "股票看盘",
                systemImage: "chart.xyaxis.line"
            ) { Text("Stock") },
            ToolRegistration(
                id: ToolID(rawValue: "podpin"), displayName: "PodPin", systemImage: "headphones"
            ) { Text("PodPin") },
        ])
        let states: [(width: CGFloat, collapsed: Bool, expandedWidth: CGFloat)] = [
            (260, false, 260), (60, true, 260), (212, false, 212),
            (120, false, 260), (60, true, 212), (260, false, 260),
        ]
        var selectionBaseline: CGFloat?

        for (index, state) in states.enumerated() {
            let root = HostSidebar(
                catalog: catalog, selection: ToolID(rawValue: "stock-watch"), onSelect: { _ in },
                onCollapse: {}, debugLogStore: DebugLogStore(isEnabled: true),
                onOpenDiagnostics: {}, isCollapsed: state.collapsed,
                expandedWidth: state.expandedWidth
            )
            .environment(\.designPalette, .light)
            .environment(\.oneBoxAccessibilityReduceMotionOverride, true)
            .frame(width: state.width, height: 600)
            let bitmap = try await render(root, size: CGSize(width: state.width, height: 600))
            let baseline = try selectedRowTop(in: bitmap, logicalWidth: state.width)
            if let selectionBaseline {
                XCTAssertEqual(baseline, selectionBaseline, accuracy: 0.5)
            } else {
                selectionBaseline = baseline
            }
            try save(bitmap, name: "sidebar-detail-\(index)-\(Int(state.width))")
        }
    }

    private func selectedRowTop(in bitmap: NSBitmapImageRep, logicalWidth: CGFloat) throws
        -> CGFloat
    {
        let scale = CGFloat(bitmap.pixelsWide) / logicalWidth
        let x = Int(16 * scale)
        var runs: [Range<Int>] = []
        var start: Int?
        for y in 0..<bitmap.pixelsHigh {
            let color = try XCTUnwrap(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
            let isAccent =
                color.blueComponent > 0.75
                && color.blueComponent - color.redComponent > 0.35
                && color.blueComponent - color.greenComponent > 0.25
            if isAccent {
                if start == nil { start = y }
            } else if let runStart = start {
                runs.append(runStart..<y)
                start = nil
            }
        }
        let row = try XCTUnwrap(runs.max { $0.count < $1.count })
        XCTAssertGreaterThan(CGFloat(row.count) / scale, 24)
        return CGFloat(row.lowerBound) / scale
    }

    private func render<Content: View>(_ root: Content, size: CGSize) async throws
        -> NSBitmapImageRep
    {
        let host = NSHostingView(rootView: root)
        host.appearance = NSAppearance(named: .aqua)
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(
            contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host
        window.orderFrontRegardless()
        defer {
            window.orderOut(nil)
            window.contentView = nil
        }
        await Task.yield()
        try await Task.sleep(for: .milliseconds(50))
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        return bitmap
    }

    private func save(_ bitmap: NSBitmapImageRep, name: String) throws {
        guard let path = ProcessInfo.processInfo.environment["ONEBOX_UI_SNAPSHOT_DIRECTORY"] else {
            return
        }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try data.write(to: directory.appendingPathComponent("\(name).png"))
    }
}

@MainActor
private final class ContentWidthRecorder {
    var widths: [CGFloat] = []
    weak var view: NSView?
}

@MainActor
private struct ContentWidthProbe: NSViewRepresentable {
    let recorder: ContentWidthRecorder

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        recorder.view = view
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSView, context: Context) -> CGSize? {
        recorder.widths.append(proposal.width ?? .infinity)
        return nil
    }
}
