import OneBoxDesignSystem
import SwiftUI

@MainActor
struct AsciiToolbar: View {
    @Bindable var session: AsciiSession
    let isExporting: Bool
    let parameterKeyboardFocus: FocusState<Bool>.Binding
    let parameterAccessibilityFocus: AccessibilityFocusState<Bool>.Binding
    let open: () -> Void
    let toggleParameters: () -> Void
    let export: () -> Void

    @Environment(\.designPalette) private var palette

    var body: some View {
        ViewThatFits(in: .horizontal) {
            toolbar(compact: false)
                .frame(minWidth: 680)
            toolbar(compact: true)
        }
        .font(DesignTypography.bodyMedium)
        .controlSize(.small)
        .frame(maxWidth: .infinity, minHeight: DesignMetrics.titlebarControlSize)
    }

    private func toolbar(compact: Bool) -> some View {
        HStack(spacing: compact ? DesignMetrics.space8 : DesignMetrics.space16) {
            Button(action: open) {
                HStack(spacing: compact ? 4 : 6) {
                    activityIcon("photo.badge.plus", isBusy: session.isImporting, compact: compact)
                    Text(compact ? "打开" : "打开图片")
                }
            }
            .buttonStyle(ToolActionButtonStyle(kind: .secondary, compact: compact))
            .keyboardShortcut("o", modifiers: .command)
            .accessibilityLabel(compact ? "打开" : "打开图片")
            .accessibilityValue(session.isImporting ? "正在读取图片" : "")
            .accessibilityInputLabels(["打开", "导入素材"])
            .fixedSize()

            HStack(spacing: DesignMetrics.space8) {
                if compact {
                    Menu {
                        Picker("画布比例", selection: $session.settings.canvasPreset) {
                            ForEach(AsciiCanvasPreset.allCases) { preset in
                                Text(preset.rawValue).tag(preset)
                            }
                        }
                        Picker("配色预设", selection: $session.settings.palettePreset) {
                            ForEach(AsciiPalettePreset.allCases) { preset in
                                Text(preset.rawValue).tag(preset)
                            }
                        }
                        Picker("动画效果", selection: $session.selectedAnimation) {
                            ForEach(AsciiAnimation.allCases) { animation in
                                Text(animation.rawValue).tag(animation)
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text("画布")
                            Image(systemName: "chevron.down")
                                .font(DesignTypography.metadata)
                                .foregroundStyle(palette.textSecondary)
                                .frame(width: 16, height: 16)
                        }
                    }
                    .menuStyle(.button)
                    .menuIndicator(.hidden)
                    .buttonStyle(ToolActionButtonStyle(kind: .secondary, compact: true))
                    .fixedSize()
                    .accessibilityLabel("画布预设")
                    .accessibilityValue(
                        "\(session.settings.canvasPreset.rawValue)，\(session.settings.palettePreset.rawValue)，\(session.settings.animation.rawValue)"
                    )
                } else {
                    ToolSegmentedPicker(
                        "画布比例",
                        selection: $session.settings.canvasPreset,
                        options: AsciiCanvasPreset.allCases.map {
                            ToolSegment($0.rawValue, value: $0)
                        }
                    )
                    .fixedSize()
                    .help("画布比例")
                    .accessibilityLabel("画布比例")
                    .accessibilityValue(session.settings.canvasPreset.rawValue)

                    AsciiSelectionMenu(
                        title: "配色预设",
                        selectedTitle: session.settings.palettePreset.rawValue,
                        selection: $session.settings.palettePreset,
                        options: AsciiPalettePreset.allCases.map {
                            ToolSegment($0.rawValue, value: $0)
                        }
                    )
                    .fixedSize()
                }
            }

            HStack(spacing: DesignMetrics.space8) {
                if !compact {
                    AsciiSelectionMenu(
                        title: "动画效果",
                        selectedTitle: session.selectedAnimation.rawValue,
                        selection: $session.selectedAnimation,
                        options: AsciiAnimation.allCases.map {
                            ToolSegment($0.rawValue, value: $0)
                        }
                    )
                    .fixedSize()
                }

                Button(
                    session.isAnimationActive ? "暂停" : "播放",
                    systemImage: session.isAnimationActive ? "pause.fill" : "play.fill",
                    action: session.togglePlayback
                )
                .buttonStyle(ToolIconButtonStyle(isSelected: session.isAnimationActive))
                .labelStyle(.iconOnly)
                .disabled(session.settings.animation == .off)
                .help(session.isAnimationActive ? "暂停" : "播放")
                .accessibilityInputLabels(["播放暂停", "播放", "暂停"])
                .foregroundStyle(palette.textPrimary)
            }

            Spacer(minLength: 0)

            HStack(spacing: DesignMetrics.space8) {
                Button(
                    session.isInspectorPresented ? "收起参数" : "显示参数",
                    systemImage: "sidebar.right",
                    action: toggleParameters
                )
                .buttonStyle(ToolIconButtonStyle(isSelected: session.isInspectorPresented))
                .labelStyle(.iconOnly)
                .foregroundStyle(palette.textPrimary)
                .help(session.isInspectorPresented ? "收起参数" : "显示参数")
                .accessibilityValue(session.isInspectorPresented ? "已打开" : "已关闭")
                .accessibilityInputLabels(["参数", "显示参数", "收起参数"])
                .accessibilityIdentifier("ascii.inspector-toggle")
                .focused(parameterKeyboardFocus)
                .accessibilityFocused(parameterAccessibilityFocus)

                Button(action: export) {
                    HStack(spacing: compact ? 4 : 6) {
                        activityIcon("square.and.arrow.down", isBusy: isExporting, compact: compact)
                        Text("导出 PNG")
                    }
                }
                .buttonStyle(ToolActionButtonStyle(kind: .primary, compact: compact))
                .keyboardShortcut("e", modifiers: .command)
                .disabled(session.source == nil || !session.isMetalReady || isExporting)
                .accessibilityLabel("导出 PNG")
                .accessibilityValue(isExporting ? "正在导出静态图片" : "")
                .accessibilityInputLabels(["导出 PNG", "导出静态图片"])
                .fixedSize()
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func activityIcon(_ systemImage: String, isBusy: Bool, compact: Bool) -> some View {
        ZStack {
            if isBusy {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: systemImage)
                    .resizable()
                    .scaledToFit()
            }
        }
        .frame(width: compact ? 18 : 20, height: compact ? 18 : 20)
        .accessibilityHidden(true)
    }
}
