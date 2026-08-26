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
        guard factor.isFinite, factor > 0 else { return }
        scale = (scale * factor).clamped(to: 0.25...8)
    }

    mutating func zoom(by factor: Double, around anchor: CGPoint, in viewportSize: CGSize) {
        guard factor.isFinite, factor > 0, viewportSize.width > 0, viewportSize.height > 0
        else { return }

        let oldScale = scale
        let newScale = (oldScale * factor).clamped(to: 0.25...8)
        let appliedFactor = newScale / oldScale
        let normalizedAnchor = CGPoint(
            x: anchor.x / viewportSize.width,
            y: anchor.y / viewportSize.height
        )
        let center = CGPoint(x: 0.5 + offset.x, y: 0.5 + offset.y)
        let newCenter = CGPoint(
            x: center.x + (1 - appliedFactor) * (normalizedAnchor.x - center.x),
            y: center.y + (1 - appliedFactor) * (normalizedAnchor.y - center.y)
        )

        scale = newScale
        offset = CGPoint(x: newCenter.x - 0.5, y: newCenter.y - 0.5)
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
