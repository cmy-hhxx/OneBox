import SwiftUI

struct WindowGeometryConfigurator: NSViewRepresentable {
    let minimumWindowSize: CGSize
    let forcedWindowSize: CGSize?

    func makeNSView(context: Context) -> NSView {
        WindowGeometryView(
            minimumWindowSize: minimumWindowSize,
            forcedWindowSize: forcedWindowSize
        )
    }

    func updateNSView(_ view: NSView, context: Context) {
        guard let view = view as? WindowGeometryView else { return }

        view.minimumWindowSize = minimumWindowSize
        view.forcedWindowSize = forcedWindowSize
    }
}

final class WindowGeometryView: NSView {
    var minimumWindowSize: CGSize
    var forcedWindowSize: CGSize?
    private var didApplyInitialGeometry = false

    init(
        minimumWindowSize: CGSize,
        forcedWindowSize: CGSize?
    ) {
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
        Task { @MainActor [weak self] in
            await Task.yield()
            self?.applyGeometry(applyForcedWindowSize: true)
        }
    }

    func applyGeometry(applyForcedWindowSize: Bool = false) {
        guard let window, !didApplyInitialGeometry else { return }

        didApplyInitialGeometry = true
        window.minSize = minimumWindowSize

        if applyForcedWindowSize, let forcedWindowSize {
            var frame = window.frame
            frame.origin.y += frame.height - forcedWindowSize.height
            frame.size = forcedWindowSize
            window.setFrame(frame, display: true)
        }
    }
}
