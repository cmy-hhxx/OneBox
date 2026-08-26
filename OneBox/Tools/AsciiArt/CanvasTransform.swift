import CoreGraphics

struct CanvasTransform: Equatable, Sendable {
    private(set) var scale: Double
    private(set) var offset: CGPoint

    init(scale: Double = 1, offset: CGPoint = .zero) {
        self.scale = scale.clamped(to: 0.25...8)
        self.offset = offset
    }

    mutating func pan(by delta: CGSize, in viewportSize: CGSize) {
        guard viewportSize.width > 0, viewportSize.height > 0 else { return }
        offset.x += delta.width / viewportSize.width
        offset.y += delta.height / viewportSize.height
    }

    mutating func zoom(by factor: Double) {
        scale = (scale * factor).clamped(to: 0.25...8)
    }

    mutating func nudge(horizontal: Double, vertical: Double) {
        offset.x += horizontal
        offset.y += vertical
    }

    mutating func reset() {
        self = CanvasTransform()
    }

    func sourceCoordinate(
        for canvasCoordinate: CGPoint,
        sourceSize: CGSize,
        canvasSize: CGSize
    ) -> CGPoint {
        guard sourceSize.width > 0, sourceSize.height > 0, canvasSize.width > 0,
            canvasSize.height > 0
        else {
            return CGPoint(x: 0.5, y: 0.5)
        }

        let sourceAspect = sourceSize.width / sourceSize.height
        let canvasAspect = canvasSize.width / canvasSize.height
        let fittedSize: CGSize
        if sourceAspect > canvasAspect {
            fittedSize = CGSize(width: 1, height: canvasAspect / sourceAspect)
        } else {
            fittedSize = CGSize(width: sourceAspect / canvasAspect, height: 1)
        }
        let displayedSize = CGSize(
            width: fittedSize.width * scale,
            height: fittedSize.height * scale
        )
        let center = CGPoint(x: 0.5 + offset.x, y: 0.5 + offset.y)

        return CGPoint(
            x: (canvasCoordinate.x - center.x) / displayedSize.width + 0.5,
            y: (canvasCoordinate.y - center.y) / displayedSize.height + 0.5
        )
    }
}
