import MetalKit
import SwiftUI

@MainActor
struct AsciiMetalView: NSViewRepresentable {
    let cache: AsciiRenderCache
    let source: AsciiSource?
    let sourceRevision: Int
    let snapshot: AsciiRenderSnapshot?
    let isAnimating: Bool
    let allowsTransientWork: Bool
    let retryRevision: Int
    let onPan: (CGSize, CGSize) -> Void
    let onZoom: (Double, CGPoint, CGSize) -> Void
    let onReset: () -> Void
    let onWindowVisibilityChanged: (Bool) -> Void
    let onReadinessChanged: (Bool) -> Void

    func makeCoordinator() -> AsciiMetalCoordinator {
        AsciiMetalCoordinator(cache: cache, onReadinessChanged: onReadinessChanged)
    }

    func makeNSView(context: Context) -> InteractiveMTKView {
        let view = InteractiveMTKView(frame: .zero, device: nil)
        view.delegate = context.coordinator
        view.colorPixelFormat = .bgra8Unorm
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        view.layer?.isOpaque = false
        view.layer?.backgroundColor = NSColor.clear.cgColor
        view.framebufferOnly = true
        view.autoResizeDrawable = true
        view.isPaused = true
        view.enableSetNeedsDisplay = true
        view.onPan = onPan
        view.onZoom = onZoom
        view.onReset = onReset
        view.onWindowVisibilityChanged = onWindowVisibilityChanged
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.group)
        view.setAccessibilityLabel("ASCII 画布")
        return view
    }

    func updateNSView(_ view: InteractiveMTKView, context: Context) {
        view.onPan = onPan
        view.onZoom = onZoom
        view.onReset = onReset
        view.onWindowVisibilityChanged = onWindowVisibilityChanged
        context.coordinator.update(
            view: view,
            source: source,
            sourceRevision: sourceRevision,
            snapshot: snapshot,
            isAnimating: isAnimating,
            retryRevision: retryRevision
        )
    }

    static func dismantleNSView(_ view: InteractiveMTKView, coordinator: AsciiMetalCoordinator) {
        view.cancelInteraction()
        coordinator.stop(view: view)
        view.delegate = nil
        view.onPan = nil
        view.onZoom = nil
        view.onReset = nil
        view.onWindowVisibilityChanged = nil
    }
}
