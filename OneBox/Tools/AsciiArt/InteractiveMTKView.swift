import MetalKit

@MainActor
final class InteractiveMTKView: MTKView {
    var onPan: ((CGSize, CGSize) -> Void)?
    var onZoom: ((Double) -> Void)?
    var onReset: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }
    override var isOpaque: Bool { false }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        if event.clickCount == 2 {
            onReset?()
        }
    }

    override func mouseDragged(with event: NSEvent) {
        onPan?(
            CGSize(width: event.deltaX, height: -event.deltaY),
            bounds.size
        )
    }

    override func scrollWheel(with event: NSEvent) {
        let factor = exp(-Double(event.scrollingDeltaY) * 0.012)
        onZoom?(factor)
    }
}
