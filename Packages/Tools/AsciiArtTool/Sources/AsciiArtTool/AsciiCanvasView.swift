import OneBoxDesignSystem
import SwiftUI

@MainActor
struct AsciiCanvasView: View {
    @Bindable var session: AsciiSession
    let renderCache: AsciiRenderCache

    @Environment(\.designPalette) private var palette
    @State private var isDropTargeted = false
    @FocusState private var isCanvasFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            if let statusMessage = session.statusMessage {
                AsciiStatusBanner(
                    message: statusMessage,
                    retry: session.statusError == .metalUnavailable
                        ? { session.retryMetalPreparation() }
                        : nil
                )
                .padding(DesignMetrics.space12)
            }

            ZStack {
                canvasSurface
                    .aspectRatio(session.settings.canvasPreset.outputSize, contentMode: .fit)
                    .padding(DesignMetrics.space16)

                if session.isImporting {
                    ProgressView("正在读取图片…")
                        .font(DesignTypography.metadata)
                        .padding(DesignMetrics.space16)
                        .background(
                            palette.surface, in: .rect(cornerRadius: DesignMetrics.cornerRadius))
                }

                if isDropTargeted {
                    Label("释放以导入图片", systemImage: "photo.badge.plus")
                        .font(DesignTypography.sectionTitle)
                        .foregroundStyle(palette.accent)
                        .padding(DesignMetrics.space16)
                        .background(
                            palette.surface, in: .rect(cornerRadius: DesignMetrics.cornerRadius)
                        )
                        .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(palette.surfaceElevated)

            Rectangle()
                .fill(palette.border)
                .frame(height: 1)

            canvasControls
        }
        .background(palette.surface)
        .clipShape(.rect(cornerRadius: DesignMetrics.cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: DesignMetrics.cornerRadius)
                .strokeBorder(isDropTargeted ? palette.accent : palette.border, lineWidth: 1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(.rect)
        .dropDestination(for: URL.self, action: acceptDrop, isTargeted: dropTargetChanged)
        .accessibilityAction(named: "重置视图") { session.transform.reset() }
        .accessibilityAction(named: "放大画布") { session.transform.zoom(by: 1.2) }
        .accessibilityAction(named: "缩小画布") { session.transform.zoom(by: 1 / 1.2) }
    }

    private var canvasControls: some View {
        HStack(spacing: DesignMetrics.space8) {
            Label(outputDimensions, systemImage: "aspectratio")
                .font(DesignTypography.metadata)
                .foregroundStyle(palette.textSecondary)
                .monospacedDigit()
                .help("导出尺寸 · \(outputDimensions) 像素")

            Spacer(minLength: DesignMetrics.space8)

            HStack(spacing: DesignMetrics.space4) {
                Button("缩小画布", systemImage: "minus") {
                    session.transform.zoom(by: 1 / 1.2)
                }
                .buttonStyle(ToolIconButtonStyle())
                .labelStyle(.iconOnly)
                .help("缩小画布（−）")
                .disabled(session.transform.scale <= 0.25)

                Text(session.transform.scale.formatted(.percent.precision(.fractionLength(0))))
                    .font(DesignTypography.metadata)
                    .monospacedDigit()
                    .foregroundStyle(palette.textSecondary)
                    .frame(width: 44)
                    .accessibilityLabel("画布缩放")
                    .accessibilityValue(session.transform.scale.formatted(.percent))

                Button("放大画布", systemImage: "plus") {
                    session.transform.zoom(by: 1.2)
                }
                .buttonStyle(ToolIconButtonStyle())
                .labelStyle(.iconOnly)
                .help("放大画布（+）")
                .disabled(session.transform.scale >= 8)

                Button("重置视图", systemImage: "arrow.counterclockwise") {
                    session.transform.reset()
                }
                .buttonStyle(ToolIconButtonStyle())
                .labelStyle(.iconOnly)
                .help("重置视图（0）")
                .accessibilityHint("恢复画布的适配位置和缩放")
            }
        }
        .padding(.horizontal, DesignMetrics.space12)
        .padding(.vertical, DesignMetrics.space4)
    }

    private var outputDimensions: String {
        let size = session.settings.canvasPreset.outputSize
        return "\(Int(size.width)) × \(Int(size.height))"
    }

    private var canvasSurface: some View {
        ZStack {
            if session.settings.hasTransparentBackground {
                AsciiCheckerboard()
            }

            AsciiMetalView(
                cache: renderCache,
                source: session.source,
                sourceRevision: session.sourceRevision,
                snapshot: session.renderSnapshot,
                isAnimating: session.isAnimationActive,
                allowsTransientWork: session.allowsTransientWork,
                retryRevision: session.metalRetryRevision,
                onPan: pan,
                onZoom: zoom,
                onReset: { session.transform.reset() },
                onWindowVisibilityChanged: session.setWindowVisible,
                onReadinessChanged: session.setMetalReady
            )
            .focusable()
            .focused($isCanvasFocused)
            .focusEffectDisabled()
            .onKeyPress(.leftArrow) {
                panByKeyboard(horizontal: -1, vertical: 0)
            }
            .onKeyPress(.rightArrow) {
                panByKeyboard(horizontal: 1, vertical: 0)
            }
            .onKeyPress(.upArrow) {
                panByKeyboard(horizontal: 0, vertical: -1)
            }
            .onKeyPress(.downArrow) {
                panByKeyboard(horizontal: 0, vertical: 1)
            }
            .onKeyPress("+") {
                zoomByKeyboard(1.2)
            }
            .onKeyPress("=") {
                zoomByKeyboard(1.2)
            }
            .onKeyPress("-") {
                zoomByKeyboard(1 / 1.2)
            }
            .onKeyPress("0") {
                session.transform.reset()
                return .handled
            }
            .onKeyPress(.space) {
                session.togglePlayback()
                return .handled
            }
            .accessibilityHint("方向键平移；加号或减号缩放；空格播放或暂停；数字零重置")

            if !session.isMetalReady || session.source == nil {
                AsciiBrandPlaceholder(image: session.source?.image)
                    .accessibilityHidden(true)
            }

        }
        .background(palette.surface)
        .clipShape(.rect(cornerRadius: DesignMetrics.cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: DesignMetrics.cornerRadius)
                .stroke(
                    isDropTargeted || isCanvasFocused ? palette.accent : palette.border,
                    lineWidth: 1
                )
        }
    }

    private func pan(_ delta: CGSize, _ viewport: CGSize) {
        session.transform.pan(by: delta, in: viewport)
    }

    private func zoom(_ factor: Double, _ anchor: CGPoint, _ viewport: CGSize) {
        session.transform.zoom(by: factor, around: anchor, in: viewport)
    }

    private func panByKeyboard(horizontal: Double, vertical: Double) -> KeyPress.Result {
        session.transform.nudge(
            horizontal: horizontal * 0.04,
            vertical: vertical * 0.04
        )
        return .handled
    }

    private func zoomByKeyboard(_ factor: Double) -> KeyPress.Result {
        session.transform.zoom(by: factor)
        return .handled
    }

    private func acceptDrop(_ urls: [URL], _ location: CGPoint) -> Bool {
        guard let url = urls.first else { return false }
        session.importImage(from: url)
        return true
    }

    private func dropTargetChanged(_ targeted: Bool) {
        isDropTargeted = targeted
    }
}
