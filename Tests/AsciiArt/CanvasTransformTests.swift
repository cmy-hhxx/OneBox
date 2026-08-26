import CoreGraphics
import Testing

@testable import AsciiArtTool

@Suite("ASCII canvas transform")
struct CanvasTransformTests {
    @Test
    func `pan uses viewport-normalized distance and reset restores fit`() {
        var transform = CanvasTransform()

        transform.pan(by: CGSize(width: 100, height: -50), in: CGSize(width: 400, height: 200))
        transform.zoom(by: 2)

        #expect(transform.offset == CGPoint(x: 0.25, y: -0.25))
        #expect(transform.scale == 2)

        transform.reset()

        #expect(transform == CanvasTransform())
    }

    @Test
    func `keyboard nudges use normalized canvas distance`() {
        var transform = CanvasTransform()

        transform.nudge(horizontal: -0.04, vertical: 0.04)

        #expect(transform.offset == CGPoint(x: -0.04, y: 0.04))
    }

    @Test
    func `AppKit drag deltas follow pointer movement in canvas coordinates`() {
        let delta = InteractiveMTKView.canvasDragDelta(
            from: CGPoint(x: 100, y: 100),
            to: CGPoint(x: 124, y: 112)
        )

        #expect(delta == CGSize(width: 24, height: -12))
    }

    @Test
    func `scroll zoom follows the expected direction and device resolution`() {
        let preciseFactor = InteractiveMTKView.scrollZoomFactor(
            from: 10,
            hasPreciseScrollingDeltas: true
        )
        let wheelFactor = InteractiveMTKView.scrollZoomFactor(
            from: 1,
            hasPreciseScrollingDeltas: false
        )

        #expect(preciseFactor > 1)
        #expect(preciseFactor < wheelFactor)
    }

    @Test
    func `precise scroll zoom is independent of event splitting`() {
        let combined = InteractiveMTKView.scrollZoomFactor(
            from: 20,
            hasPreciseScrollingDeltas: true
        )
        let split = (0..<4).reduce(1.0) { factor, _ in
            factor
                * InteractiveMTKView.scrollZoomFactor(
                    from: 5,
                    hasPreciseScrollingDeltas: true
                )
        }

        #expect(abs(combined - split) < 0.000_001)
    }

    @Test
    func `pointer anchored zoom keeps the source point under the pointer`() {
        var transform = CanvasTransform(scale: 1.2, offset: CGPoint(x: 0.1, y: -0.08))
        let viewport = CGSize(width: 400, height: 200)
        let anchor = CGPoint(x: 300, y: 50)
        let normalizedAnchor = CGPoint(x: anchor.x / viewport.width, y: anchor.y / viewport.height)
        let sourceSize = CGSize(width: 1600, height: 900)
        let canvasSize = CGSize(width: 1920, height: 1080)
        let sourceBeforeZoom = transform.sourceCoordinate(
            for: normalizedAnchor,
            sourceSize: sourceSize,
            canvasSize: canvasSize
        )

        transform.zoom(by: 1.4, around: anchor, in: viewport)

        let sourceAfterZoom = transform.sourceCoordinate(
            for: normalizedAnchor,
            sourceSize: sourceSize,
            canvasSize: canvasSize
        )
        #expect(abs(sourceBeforeZoom.x - sourceAfterZoom.x) < 0.000_001)
        #expect(abs(sourceBeforeZoom.y - sourceAfterZoom.y) < 0.000_001)
    }

    @Test
    func `preview and export map the same normalized composition`() {
        let transform = CanvasTransform(scale: 1.5, offset: CGPoint(x: 0.1, y: -0.15))
        let preview = transform.sourceCoordinate(
            for: CGPoint(x: 0.4, y: 0.65),
            sourceSize: CGSize(width: 1600, height: 900),
            canvasSize: CGSize(width: 1920, height: 1080)
        )
        let export = transform.sourceCoordinate(
            for: CGPoint(x: 0.4, y: 0.65),
            sourceSize: CGSize(width: 1600, height: 900),
            canvasSize: CGSize(width: 1920, height: 1080)
        )

        #expect(preview == export)
    }
}
