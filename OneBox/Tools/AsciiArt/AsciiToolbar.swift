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
        HStack(spacing: DesignMetrics.space8) {
            Button("打开", systemImage: "folder", action: open)
                .keyboardShortcut("o", modifiers: .command)
                .accessibilityInputLabels(["打开", "导入素材"])

            if session.isImporting {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("正在读取素材")
            }

            Menu(session.settings.canvasPreset.rawValue, systemImage: "aspectratio") {
                Picker("画布比例", selection: $session.settings.canvasPreset) {
                    ForEach(AsciiCanvasPreset.allCases) { preset in
                        Text(preset.rawValue).tag(preset)
                    }
                }
            }
            .accessibilityLabel("画布比例")
            .accessibilityValue(session.settings.canvasPreset.rawValue)

            Menu(session.settings.palettePreset.rawValue, systemImage: "paintpalette") {
                Picker("配色预设", selection: $session.settings.palettePreset) {
                    ForEach(AsciiPalettePreset.allCases) { preset in
                        Text(preset.rawValue).tag(preset)
                    }
                }
            }
            .accessibilityLabel("配色预设")
            .accessibilityValue(session.settings.palettePreset.rawValue)

            Button(
                session.isAnimationActive ? "暂停" : "播放",
                systemImage: session.isAnimationActive ? "pause.fill" : "play.fill",
                action: session.togglePlayback
            )
            .disabled(session.settings.animation == .off)
            .accessibilityInputLabels(["播放暂停", "播放", "暂停"])

            Button("参数", systemImage: "slider.horizontal.3", action: toggleParameters)
                .accessibilityValue(session.isInspectorPresented ? "已打开" : "已关闭")
                .accessibilityFocused(parameterFocus)

            Spacer(minLength: 0)

            Button("导出静态 PNG", systemImage: "square.and.arrow.down", action: export)
                .keyboardShortcut("e", modifiers: .command)
                .disabled(session.source == nil || !session.isMetalReady || isExporting)
                .accessibilityInputLabels(["导出 PNG", "导出静态图片"])

            if isExporting {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("正在导出静态 PNG")
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .padding(.horizontal, DesignMetrics.space12)
        .frame(minHeight: 40)
        .background(palette.surface)
        .clipShape(.rect(cornerRadius: DesignMetrics.cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: DesignMetrics.cornerRadius)
                .stroke(palette.border, lineWidth: 1)
        }
    }
}
