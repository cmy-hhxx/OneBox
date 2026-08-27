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
    func `captured drag maps device movement to the expected canvas direction`() {
        let delta = InteractiveMTKView.canvasDragDelta(deltaX: 24, deltaY: 12)

        #expect(delta == CGSize(width: 24, height: 12))
    }

    @Test
    func `repeated relative drags keep panning without an offset boundary`() {
        var transform = CanvasTransform()

        for _ in 0..<100 {
            transform.pan(
                by: InteractiveMTKView.canvasDragDelta(deltaX: 80, deltaY: -40),
                in: CGSize(width: 400, height: 200)
            )
        }

        #expect(abs(transform.offset.x - 20) < 0.000_001)
        #expect(abs(transform.offset.y + 20) < 0.000_001)
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
    func `pointer anchored zoom moves the canvas center around the pointer`() {
        var transform = CanvasTransform(scale: 1.2, offset: CGPoint(x: 0.1, y: -0.08))
        let viewport = CGSize(width: 400, height: 200)
        let anchor = CGPoint(x: 300, y: 50)

        transform.zoom(by: 1.4, around: anchor, in: viewport)

        #expect(abs(transform.scale - 1.68) < 0.000_001)
        #expect(abs(transform.offset.x - 0.04) < 0.000_001)
        #expect(abs(transform.offset.y - -0.012) < 0.000_001)
    }
}
