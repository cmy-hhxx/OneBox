import AppKit
import OneBoxDesignSystem
import OneBoxRuntime
import SwiftUI
import XCTest

@testable import OneBoxHost

@MainActor
final class DebugLogLayoutTests: XCTestCase {
    func testLogRecordAndControlsRemainReadableAtBothWindowSizes() async throws {
        let store = DebugLogStore(isEnabled: true)
        let entries: [(String, String, String)] = [
            ("ascii-art", "ASCII 工坊", "character.textbox"),
            ("stock-watch", "股票看盘", "chart.xyaxis.line"),
            ("podpin", "PodPin", "headphones"),
        ]
        let catalog = ToolCatalog(
            registrations: entries.map { id, name, symbol in
                ToolRegistration(id: ToolID(rawValue: id), displayName: name, systemImage: symbol) {
                    Text(name)
                }
            })
        store.diagnostics(for: ToolID(rawValue: "stock-watch"), name: "股票看盘")
            .record(
                NSError(
                    domain: "NSURLErrorDomain", code: -1001,
                    userInfo: [
                        NSLocalizedDescriptionKey: "The request timed out.",
                        NSDebugDescriptionErrorKey:
                            "GET https://example.invalid/quote?token=fixture\nThe server did not respond within the configured timeout.",
                    ]), operation: "quote.tencent")
        store.diagnostics(for: ToolID(rawValue: "ascii-art"), name: "ASCII 工坊")
            .record(message: "Image decoder: unsupported image format", operation: "Import image")
        for _ in 0..<20 where store.entries.count < 2 { await Task.yield() }
        XCTAssertEqual(store.entries.count, 2)
        store.selectedModuleID = ToolID(rawValue: "stock-watch")

        for size in [CGSize(width: 880, height: 600), CGSize(width: 680, height: 440)] {
            let root = DebugLogView(store: store, catalog: catalog, copyText: { _ in })
                .environment(\.designPalette, .light)
                .frame(width: size.width, height: size.height)
            let png = try await render(root, size: size)
            try save(png, name: "logs-\(Int(size.width))")
        }

        let activeRoot = DebugLogView(store: store, catalog: catalog, copyText: { _ in })
            .environment(\.designPalette, .light)
            .environment(\.controlActiveState, .active)
            .frame(width: 680, height: 440)
        try await save(
            render(activeRoot, size: CGSize(width: 680, height: 440)), name: "logs-active-680")

        for size in [CGSize(width: 1048, height: 280), CGSize(width: 899, height: 220)] {
            let embedded = DebugLogView(
                store: store, catalog: catalog, copyText: { _ in }, onClose: {}
            )
            .environment(\.designPalette, .light)
            .environment(\.controlActiveState, .active)
            .frame(width: size.width, height: size.height)
            try await save(
                render(embedded, size: size),
                name: "logs-embedded-\(Int(size.width))-\(Int(size.height))")
        }

        let sidebar = HostSidebar(
            catalog: catalog, selection: ToolID(rawValue: "stock-watch"),
            onSelect: { _ in }, onCollapse: {}, debugLogStore: store, onOpenDiagnostics: {}
        )
        .environment(\.designPalette, .light)
        .frame(width: DesignMetrics.sidebarWidth, height: 648)
        try await save(
            render(sidebar, size: CGSize(width: DesignMetrics.sidebarWidth, height: 648)),
            name: "sidebar")
    }

    func testEmbeddedEmptyStatesFitMinimumPanelHeight() async throws {
        let catalog = ToolCatalog(registrations: [
            ToolRegistration(id: ToolID(rawValue: "ascii-art"), displayName: "ASCII 工坊") {
                Text("ASCII")
            },
            ToolRegistration(id: ToolID(rawValue: "stock-watch"), displayName: "股票看盘") {
                Text("Stock")
            },
            ToolRegistration(id: ToolID(rawValue: "podpin"), displayName: "PodPin") {
                Text("PodPin")
            },
        ])
        for enabled in [false, true] {
            let root = DebugLogView(
                store: DebugLogStore(isEnabled: enabled), catalog: catalog,
                copyText: { _ in }, onClose: {}
            )
            .environment(\.designPalette, .light)
            .frame(width: 899, height: 220)
            try await save(
                render(root, size: CGSize(width: 899, height: 220)),
                name: "logs-embedded-empty-\(enabled ? "enabled" : "disabled")")
        }
    }

    func testCollapsedSidebarRetainsToolAndDiagnosticsControls() async throws {
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
        let sidebar = HostSidebar(
            catalog: catalog, selection: ToolID(rawValue: "stock-watch"),
            onSelect: { _ in }, onCollapse: {}, debugLogStore: DebugLogStore(),
            onOpenDiagnostics: {}, isCollapsed: true
        )
        .environment(\.designPalette, .light).frame(width: 60, height: 600)
        try await save(
            render(sidebar, size: CGSize(width: 60, height: 600)), name: "sidebar-collapsed")
    }

    private func render<Content: View>(_ root: Content, size: CGSize) async throws -> Data {
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
        XCTAssertEqual(host.frame.width, size.width, accuracy: 1)
        XCTAssertEqual(host.frame.height, size.height, accuracy: 1)
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        XCTAssertGreaterThan(data.count, 5_000)
        return data
    }

    private func save(_ data: Data, name: String) throws {
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let path = ProcessInfo.processInfo.environment["ONEBOX_UI_SNAPSHOT_DIRECTORY"] {
            let directory = URL(fileURLWithPath: path, isDirectory: true)
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true)
            try data.write(to: directory.appendingPathComponent("\(name).png"))
        }
    }
}
