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
