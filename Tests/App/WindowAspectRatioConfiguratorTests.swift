import AppKit
import XCTest
@testable import OneBox

final class WindowAspectRatioConfiguratorTests: XCTestCase {
    @MainActor
    func testAppliesWindowGeometry() {
        let window = makeWindow(size: CGSize(width: 800, height: 600))
        let aspectRatio = CGSize(width: 1048, height: 648)
        let minimumSize = CGSize(width: 899, height: 556)
        let view = WindowGeometryView(
            aspectRatio: aspectRatio,
            minimumWindowSize: minimumSize,
            forcedWindowSize: nil
        )
        window.contentView = view

        view.applyGeometry()

        XCTAssertEqual(window.aspectRatio, aspectRatio)
        XCTAssertEqual(window.minSize, minimumSize)
    }

    @MainActor
    func testAppliesForcedSizeOnlyOnce() {
        let initialSize = CGSize(width: 800, height: 600)
        let forcedSize = CGSize(width: 1048, height: 648)
        let window = makeWindow(size: initialSize)
        let view = WindowGeometryView(
            aspectRatio: forcedSize,
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
    private func makeWindow(size: CGSize) -> NSWindow {
        NSWindow(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )
    }
}
