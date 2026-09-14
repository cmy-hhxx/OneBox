import OneBoxDesignSystem
import SwiftUI

@MainActor
struct AsciiInspector: View {
    @Bindable var session: AsciiSession

    @Environment(\.designPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: DesignMetrics.space24) {
            characterControls
            renderControls
            animationControls
        }
        .font(DesignTypography.body)
        .controlSize(.small)
        .toggleStyle(ToolSwitchStyle())
    }

    private var characterControls: some View {
        InspectorSection(title: "字符") {
            HStack {
                Text("字符集")
                Spacer(minLength: DesignMetrics.space8)
                AsciiSelectionMenu(
                    title: "字符集",
                    selectedTitle: session.selectedCharacterSet.rawValue,
                    selection: $session.selectedCharacterSet,
                    options: AsciiCharacterSet.allCases.map {
                        ToolSegment($0.rawValue, value: $0)
                    }
                )
                .frame(width: 128)
            }

            if session.selectedCharacterSet == .custom {
                ToolTextField("自定义字符", text: $session.customCharacters)
                    .font(DesignTypography.diagnostic)
                    .accessibilityHint("最多六十四个字符；重复字符会增加权重")

                if session.settings.characters.validation == .empty {
                    Label("至少输入一个字符；当前仍使用上次有效值。", systemImage: "exclamationmark.circle")
                        .font(DesignTypography.metadata)
                        .foregroundStyle(palette.negative)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            AsciiSliderRow(
                title: "字符大小",
                value: $session.settings.characterSize,
                range: 5...20,
                step: 1,
                valueText: "\(Int(session.settings.characterSize)) px"
            )
            AsciiSliderRow(
                title: "密度",
                value: $session.settings.density,
                range: 0...1,
                valueText: session.settings.density.formatted(
                    .percent.precision(.fractionLength(0)))
            )
        }
    }

    private var renderControls: some View {
        InspectorSection(title: "图像") {
            AsciiSliderRow(
                title: "对比度",
                value: $session.settings.contrast,
                range: 0.4...2,
                valueText: session.settings.contrast.formatted(
                    .number.precision(.fractionLength(2)))
            )
            Toggle("反色", isOn: $session.settings.isInverted)
            Toggle("透明背景", isOn: $session.settings.hasTransparentBackground)
        }
    }

    private var animationControls: some View {
        InspectorSection(title: "动画") {
            HStack {
                Text("效果")
                Spacer(minLength: DesignMetrics.space8)
                AsciiSelectionMenu(
                    title: "动画效果",
                    selectedTitle: session.selectedAnimation.rawValue,
                    selection: $session.selectedAnimation,
                    options: AsciiAnimation.allCases.map {
                        ToolSegment($0.rawValue, value: $0)
                    }
                )
                .frame(width: 128)
            }

            AsciiSliderRow(
                title: "动画强度",
                value: $session.settings.animationStrength,
                range: 0...1,
                valueText: session.settings.animationStrength.formatted(
                    .percent.precision(.fractionLength(0))
                )
            )
            .disabled(session.settings.animation == .off)

            Label("PNG 导出为静态画面", systemImage: "photo")
                .font(DesignTypography.metadata)
                .foregroundStyle(palette.textSecondary)
        }
    }
}
