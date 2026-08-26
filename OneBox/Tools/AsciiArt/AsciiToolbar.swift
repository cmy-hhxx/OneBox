import OneBoxDesignSystem
import SwiftUI

@MainActor
struct AsciiToolbar: View {
    @Bindable var session: AsciiSession
    let isExporting: Bool
    let parameterFocus: AccessibilityFocusState<Bool>.Binding
    let open: () -> Void
    let toggleParameters: () -> Void
    let export: () -> Void

    @Environment(\.designPalette) private var palette

    var body: some View {
        HStack(spacing: DesignMetrics.space16) {
            Button("打开素材", systemImage: "folder", action: open)
                .buttonStyle(.borderless)
                .keyboardShortcut("o", modifiers: .command)
                .accessibilityInputLabels(["打开", "导入素材"])
                .foregroundStyle(palette.textPrimary)

            if session.isImporting {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("正在读取素材")
            }

            HStack(spacing: DesignMetrics.space8) {
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

                Menu(session.settings.palettePreset.rawValue, systemImage: "paintpalette") {
                    ForEach(AsciiPalettePreset.allCases) { preset in
                        Button(action: { selectPalette(preset) }) {
                            if preset == session.settings.palettePreset {
                                Label(preset.rawValue, systemImage: "checkmark")
                            } else {
                                Text(preset.rawValue)
                            }
                        }
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("配色预设")
                .accessibilityLabel("配色预设")
                .accessibilityValue(session.settings.palettePreset.rawValue)
                .foregroundStyle(palette.textPrimary)
                .tint(palette.textPrimary)

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
                .accessibilityFocused(parameterFocus)
            }

            Spacer(minLength: DesignMetrics.space8)

            Button(
                session.isAnimationActive ? "暂停" : "播放",
                systemImage: session.isAnimationActive ? "pause.fill" : "play.fill",
                action: session.togglePlayback
            )
            .buttonStyle(.borderless)
            .disabled(session.settings.animation == .off)
            .accessibilityInputLabels(["播放暂停", "播放", "暂停"])
            .foregroundStyle(palette.textPrimary)

            Button("导出 PNG", systemImage: "square.and.arrow.down", action: export)
                .buttonStyle(.borderedProminent)
                .tint(palette.accent)
                .keyboardShortcut("e", modifiers: .command)
                .disabled(session.source == nil || !session.isMetalReady || isExporting)
                .accessibilityInputLabels(["导出 PNG", "导出静态图片"])

            if isExporting {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("正在导出静态 PNG")
            }
        }
        .font(DesignTypography.bodyMedium)
        .controlSize(.regular)
        .frame(minHeight: DesignMetrics.titlebarControlSize)
        .padding(.horizontal, DesignMetrics.space4)
    }

    private func selectPalette(_ preset: AsciiPalettePreset) {
        session.settings.palettePreset = preset
    }
}
