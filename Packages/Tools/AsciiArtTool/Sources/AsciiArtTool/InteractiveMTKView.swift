import MetalKit

@MainActor
final class InteractiveMTKView: MTKView {
    var onPan: ((CGSize, CGSize) -> Void)?
    var onZoom: ((Double, CGPoint, CGSize) -> Void)?
    var onReset: (() -> Void)?

    private var isInfiniteDragActive = false

    override var acceptsFirstResponder: Bool { true }
    override var isOpaque: Bool { false }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        if event.clickCount == 2 {
            onReset?()
        }
    }

    override func mouseDragged(with event: NSEvent) {
        beginInfiniteDragIfPossible()
        onPan?(
            Self.canvasDragDelta(deltaX: event.deltaX, deltaY: event.deltaY),
            bounds.size
        )
    }

    override func mouseUp(with event: NSEvent) {
        cancelInteraction()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(cancelInteractionForNotification),
            name: NSWindow.didResignKeyNotification,
            object: window
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(cancelInteractionForNotification),
            name: NSApplication.didResignActiveNotification,
            object: nil
        )
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        NotificationCenter.default.removeObserver(self)
        cancelInteraction()
        super.viewWillMove(toWindow: newWindow)
    }

    nonisolated static func canvasDragDelta(deltaX: CGFloat, deltaY: CGFloat) -> CGSize {
        CGSize(width: deltaX, height: deltaY)
    }

    func cancelInteraction() {
        guard isInfiniteDragActive else { return }
        CGAssociateMouseAndMouseCursorPosition(1)
        NSCursor.unhide()
        isInfiniteDragActive = false
    }

    private func beginInfiniteDragIfPossible() {
        guard !isInfiniteDragActive,
            CGAssociateMouseAndMouseCursorPosition(0) == .success
        else { return }
        NSCursor.hide()
        isInfiniteDragActive = true
    }

    @objc private func cancelInteractionForNotification(_ notification: Notification) {
        cancelInteraction()
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
