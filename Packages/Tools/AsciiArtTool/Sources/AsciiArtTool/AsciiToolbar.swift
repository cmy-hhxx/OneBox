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
        .controlSize(.regular)
        .frame(maxWidth: .infinity, minHeight: DesignMetrics.titlebarControlSize)
    }

    private func toolbar(compact: Bool) -> some View {
        HStack(spacing: DesignMetrics.space16) {
            HStack(spacing: DesignMetrics.space8) {
                Button("打开", systemImage: "folder", action: open)
                    .buttonStyle(.borderless)
                    .keyboardShortcut("o", modifiers: .command)
                    .accessibilityInputLabels(["打开", "导入素材"])
                    .foregroundStyle(palette.textPrimary)

                if session.isImporting {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("正在读取素材")
                }
            }

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
                        Label("画布", systemImage: "slider.horizontal.3")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .accessibilityLabel("画布预设")
                    .accessibilityValue(
                        "\(session.settings.canvasPreset.rawValue)，\(session.settings.palettePreset.rawValue)，\(session.settings.animation.rawValue)"
                    )
                } else {
                    Picker("画布比例", selection: $session.settings.canvasPreset) {
                        ForEach(AsciiCanvasPreset.allCases) { preset in
                            Text(preset.rawValue).tag(preset)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    .help("画布比例")
                    .accessibilityLabel("画布比例")
                    .accessibilityValue(session.settings.canvasPreset.rawValue)

                    Picker("配色预设", selection: $session.settings.palettePreset) {
                        ForEach(AsciiPalettePreset.allCases) { preset in
                            Text(preset.rawValue).tag(preset)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .fixedSize()
                    .help("配色预设")
                    .accessibilityLabel("配色预设")
                    .accessibilityValue(session.settings.palettePreset.rawValue)
                    .foregroundStyle(palette.textPrimary)
                    .tint(palette.textPrimary)
                }
            }

            HStack(spacing: DesignMetrics.space8) {
                if !compact {
                    Picker("动画效果", selection: $session.selectedAnimation) {
                        ForEach(AsciiAnimation.allCases) { animation in
                            Text(animation.rawValue).tag(animation)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .fixedSize()
                    .help("动画效果")
                    .accessibilityLabel("动画效果")
                    .accessibilityValue(session.settings.animation.rawValue)
                    .foregroundStyle(palette.textPrimary)
                    .tint(palette.textPrimary)
                }

                Button(
                    session.isAnimationActive ? "暂停" : "播放",
                    systemImage: session.isAnimationActive ? "pause.fill" : "play.fill",
                    action: session.togglePlayback
                )
                .buttonStyle(.borderless)
                .labelStyle(.iconOnly)
                .frame(width: DesignMetrics.titlebarControlSize)
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
                .buttonStyle(.borderless)
                .labelStyle(.iconOnly)
                .frame(width: DesignMetrics.titlebarControlSize)
                .foregroundStyle(palette.textPrimary)
                .help(session.isInspectorPresented ? "收起参数" : "显示参数")
                .accessibilityValue(session.isInspectorPresented ? "已打开" : "已关闭")
                .accessibilityInputLabels(["参数", "显示参数", "收起参数"])
                .accessibilityIdentifier("ascii.inspector-toggle")
                .focused(parameterKeyboardFocus)
                .accessibilityFocused(parameterAccessibilityFocus)

                Button("导出 PNG", systemImage: "square.and.arrow.down", action: export)
                    .buttonStyle(.borderedProminent)
                    .tint(palette.accent)
                    .keyboardShortcut("e", modifiers: .command)
                    .disabled(session.source == nil || !session.isMetalReady || isExporting)
                    .accessibilityInputLabels(["导出 PNG", "导出静态图片"])
                    .fixedSize()

                if isExporting {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("正在导出静态 PNG")
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

}
