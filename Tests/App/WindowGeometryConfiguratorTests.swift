import AppKit
import XCTest

@testable import OneBox

final class WindowGeometryConfiguratorTests: XCTestCase {
    @MainActor
    func testAppliesMinimumSizeWithoutChangingAspectRatio() {
        let window = makeWindow(size: CGSize(width: 800, height: 600))
        let aspectRatio = CGSize(width: 1048, height: 648)
        let minimumSize = CGSize(width: 899, height: 556)
        window.aspectRatio = aspectRatio
        let view = WindowGeometryView(
            minimumWindowSize: minimumSize,
            forcedWindowSize: nil
        )
        window.contentView = view

        view.applyGeometry()

        XCTAssertEqual(window.aspectRatio, aspectRatio)
        XCTAssertEqual(window.minSize, minimumSize)
    }

    @MainActor
    func testWindowAttachmentDefersGeometryUntilSwiftUIDefaultSizeCanSettle() {
        let window = makeWindow(size: CGSize(width: 800, height: 600))
        let originalMinimumSize = window.minSize
        let view = WindowGeometryView(
            minimumWindowSize: CGSize(width: 899, height: 556),
            forcedWindowSize: nil
        )

        window.contentView = view

        XCTAssertEqual(window.minSize, originalMinimumSize)
    }

    @MainActor
    func testAppliesForcedSizeOnlyOnce() {
        let initialSize = CGSize(width: 800, height: 600)
        let forcedSize = CGSize(width: 1048, height: 648)
        let window = makeWindow(size: initialSize)
        let view = WindowGeometryView(
            minimumWindowSize: CGSize(width: 899, height: 556),
            forcedWindowSize: forcedSize
        )
        window.contentView = view

        view.applyGeometry(applyForcedWindowSize: true)
        XCTAssertEqual(window.frame.size, forcedSize)

        view.forcedWindowSize = CGSize(width: 1200, height: 800)
        view.applyGeometry(applyForcedWindowSize: true)

        XCTAssertEqual(window.frame.size, forcedSize)
    }

    @MainActor
    func testDoesNotReapplyGeometryAfterInitialWindowAttachment() {
        let initialMinimumSize = CGSize(width: 899, height: 556)
        let window = makeWindow(size: CGSize(width: 1_048, height: 648))
        let view = WindowGeometryView(
            minimumWindowSize: initialMinimumSize,
            forcedWindowSize: nil
        )
        window.contentView = view

        view.applyGeometry()
        view.minimumWindowSize = CGSize(width: 1_200, height: 800)
        view.applyGeometry()

        XCTAssertEqual(window.minSize, initialMinimumSize)
    }

    @MainActor
    private func makeWindow(size: CGSize) -> NSWindow {
        NSWindow(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )
    }
}
