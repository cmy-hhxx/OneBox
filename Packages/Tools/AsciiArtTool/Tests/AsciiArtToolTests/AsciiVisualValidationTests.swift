import AppKit
import Foundation
import OneBoxDesignSystem
import SwiftUI
import XCTest

@testable import AsciiArtTool

@MainActor
final class AsciiVisualValidationTests: XCTestCase {
    func testWorkspaceReferenceRendersAtDefaultAndMinimumSizes() async throws {
        _ = NSApplication.shared
        let references: [(name: String, size: CGSize, inspector: Bool)] = [
            ("ascii-default", CGSize(width: 716, height: 510), false),
            ("ascii-minimum", CGSize(width: 616, height: 418), false),
            ("ascii-narrow-workspace", CGSize(width: 356, height: 418), false),
            ("ascii-default-inspector", CGSize(width: 716, height: 510), true),
            ("ascii-minimum-inspector", CGSize(width: 616, height: 418), true),
        ]
        for reference in references {
            let session = AsciiSession()
            session.prepareInitialSource()
            session.isInspectorPresented = reference.inspector
            let cache = AsciiRenderCache(deviceProvider: TestAsciiMetalDeviceProvider())
            try await render(
                AsciiArtView(session: session, renderCache: cache),
                size: reference.size,
                name: reference.name
            )
            await session.shutdown()
        }
    }

    func testInspectorReferenceRendersAtNativeWidth() async throws {
        let session = AsciiSession()
        let inspector = ScrollView {
            AsciiInspector(session: session)
                .padding(DesignMetrics.space16)
        }
        .background(DesignPalette.light.surface)
        try await render(
            inspector,
            size: CGSize(width: DesignMetrics.inspectorWidth, height: 600),
            name: "ascii-inspector-content"
        )
        session.selectedCharacterSet = .custom
        session.customCharacters = " .:-=+*#%@"
        session.settings.isInverted = true
        session.settings.hasTransparentBackground = true
        session.selectedAnimation = .wave
        try await render(
            inspector,
            size: CGSize(width: DesignMetrics.inspectorWidth, height: 650),
            name: "ascii-inspector-custom"
        )
        await session.shutdown()
    }

    func testErrorReferenceRendersAtNarrowWidth() async throws {
        let session = AsciiSession()
        session.prepareInitialSource()
        session.report(.decodeFailed)
        let cache = AsciiRenderCache(deviceProvider: TestAsciiMetalDeviceProvider())
        try await render(
            AsciiArtView(session: session, renderCache: cache),
            size: CGSize(width: 356, height: 418),
            name: "ascii-error-narrow"
        )
        await session.shutdown()
    }

    private func render(
        _ content: some View,
        size: CGSize,
        name: String
    ) async throws {
        let root =
            content
            .environment(\.designPalette, .light)
            .environment(\.oneBoxAccessibilityReduceMotionOverride, true)
            .tint(DesignPalette.light.accent)
            .background(DesignPalette.light.background)
            .preferredColorScheme(.light)
            .transaction { $0.disablesAnimations = true }
            .frame(width: size.width, height: size.height)
        let host = NSHostingView(rootView: root)
        host.appearance = NSAppearance(named: .aqua)
        host.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(
            contentRect: host.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.contentView = host
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        window.orderFrontRegardless()
        defer {
            window.orderOut(nil)
            window.contentView = nil
        }
        try await Task.sleep(for: .milliseconds(150))
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()
        XCTAssertEqual(host.bounds.size, size)

        // NSView's bitmap does not include CAMetalLayer or native inspector presentation.
        // These references validate SwiftUI chrome; app-hosted UI tests own action visibility.
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        XCTAssertGreaterThan(png.count, 1_000)
        if let directory = ProcessInfo.processInfo.environment["ONEBOX_UI_SNAPSHOT_DIRECTORY"] {
            let output = URL(fileURLWithPath: directory, isDirectory: true)
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            try png.write(to: output.appendingPathComponent("\(name).png"))
        } else {
            let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }
}
