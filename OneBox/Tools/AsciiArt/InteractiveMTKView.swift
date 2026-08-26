import MetalKit

@MainActor
final class InteractiveMTKView: MTKView {
    var onPan: ((CGSize, CGSize) -> Void)?
    var onZoom: ((Double, CGPoint, CGSize) -> Void)?
    var onReset: (() -> Void)?

    private var lastDragLocation: CGPoint?

    override var acceptsFirstResponder: Bool { true }
    override var isOpaque: Bool { false }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        lastDragLocation = convert(event.locationInWindow, from: nil)
        if event.clickCount == 2 {
            onReset?()
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        guard let lastDragLocation else {
            self.lastDragLocation = location
            return
        }
        let delta = Self.canvasDragDelta(
            from: lastDragLocation,
            to: location
        )
        self.lastDragLocation = location
        onPan?(delta, bounds.size)
    }

    override func mouseUp(with event: NSEvent) {
        lastDragLocation = nil
    }

    nonisolated static func canvasDragDelta(
        from previousLocation: CGPoint,
        to currentLocation: CGPoint
    ) -> CGSize {
        CGSize(
            width: currentLocation.x - previousLocation.x,
            height: previousLocation.y - currentLocation.y
        )
    }

    override func scrollWheel(with event: NSEvent) {
        guard event.momentumPhase.isEmpty else { return }
        let factor = Self.scrollZoomFactor(
            from: event.scrollingDeltaY,
            hasPreciseScrollingDeltas: event.hasPreciseScrollingDeltas
        )
        zoom(by: factor, at: event)
    }

    override func magnify(with event: NSEvent) {
        zoom(by: Self.magnificationZoomFactor(from: event.magnification), at: event)
    }

    nonisolated static func scrollZoomFactor(
        from scrollingDeltaY: CGFloat,
        hasPreciseScrollingDeltas: Bool
    ) -> Double {
        let delta = Double(scrollingDeltaY)
        let exponent =
            hasPreciseScrollingDeltas
            ? delta.clamped(to: -40...40) * 0.006
            : delta.clamped(to: -3...3) * 0.1
        return exp(exponent)
    }

    nonisolated static func magnificationZoomFactor(from magnification: CGFloat) -> Double {
        max(0.1, 1 + Double(magnification))
    }

    nonisolated static func canvasLocation(
        from viewLocation: CGPoint,
        in viewportSize: CGSize
    ) -> CGPoint {
        CGPoint(x: viewLocation.x, y: viewportSize.height - viewLocation.y)
    }

    private func zoom(by factor: Double, at event: NSEvent) {
        let viewportSize = bounds.size
        let viewLocation = convert(event.locationInWindow, from: nil)
        onZoom?(
            factor,
            Self.canvasLocation(from: viewLocation, in: viewportSize),
            viewportSize
        )
    }
}
