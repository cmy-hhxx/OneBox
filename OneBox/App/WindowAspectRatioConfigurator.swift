import SwiftUI

struct WindowAspectRatioConfigurator: NSViewRepresentable {
    let aspectRatio: CGSize
    let minimumWindowSize: CGSize
    let forcedWindowSize: CGSize?

    func makeNSView(context: Context) -> NSView {
        WindowGeometryView(
            aspectRatio: aspectRatio,
            minimumWindowSize: minimumWindowSize,
            forcedWindowSize: forcedWindowSize
        )
    }

    func updateNSView(_ view: NSView, context: Context) {
        guard let view = view as? WindowGeometryView else { return }

        view.aspectRatio = aspectRatio
        view.minimumWindowSize = minimumWindowSize
        view.forcedWindowSize = forcedWindowSize
        view.applyGeometry()
    }
}

final class WindowGeometryView: NSView {
    var aspectRatio: CGSize
    var minimumWindowSize: CGSize
    var forcedWindowSize: CGSize?
    private var didApplyForcedWindowSize = false

    init(
        aspectRatio: CGSize,
        minimumWindowSize: CGSize,
        forcedWindowSize: CGSize?
    ) {
        self.aspectRatio = aspectRatio
        self.minimumWindowSize = minimumWindowSize
        self.forcedWindowSize = forcedWindowSize
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyGeometry()
        Task { @MainActor [weak self] in
            await Task.yield()
            self?.applyGeometry(applyForcedWindowSize: true)
        }
    }

    func applyGeometry(applyForcedWindowSize: Bool = false) {
        guard let window else { return }

        window.aspectRatio = aspectRatio
        window.minSize = minimumWindowSize

        if applyForcedWindowSize, let forcedWindowSize, !didApplyForcedWindowSize {
            var frame = window.frame
            frame.origin.y += frame.height - forcedWindowSize.height
            frame.size = forcedWindowSize
            window.setFrame(frame, display: true)
            didApplyForcedWindowSize = true
        }
    }
}
