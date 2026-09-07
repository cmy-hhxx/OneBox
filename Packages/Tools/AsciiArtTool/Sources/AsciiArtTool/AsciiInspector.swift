import OneBoxDesignSystem
import SwiftUI

@MainActor
struct AsciiInspector: View {
    @Bindable var session: AsciiSession

    @Environment(\.designPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: DesignMetrics.space16) {
            characterControls
            renderControls
            animationControls
        }
    }

    private var characterControls: some View {
        VStack(alignment: .leading, spacing: DesignMetrics.space8) {
            Text("字符")
                .font(DesignTypography.sectionTitle)

            Picker("字符集", selection: $session.selectedCharacterSet) {
                ForEach(AsciiCharacterSet.allCases) { characterSet in
                    Text(characterSet.rawValue).tag(characterSet)
                }
            }

            if session.selectedCharacterSet == .custom {
                TextField("自定义字符", text: $session.customCharacters)
                    .font(.system(.body, design: .monospaced))
                    .accessibilityHint("最多六十四个字符；重复字符会增加权重")

                if session.settings.characters.validation == .empty {
                    Text("至少输入一个字符；当前仍使用上次有效值。")
                        .font(DesignTypography.metadata)
                        .foregroundStyle(palette.negative)
                }
            }
        }
    }

    private var renderControls: some View {
        VStack(alignment: .leading, spacing: DesignMetrics.space12) {
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
                step: 0.01,
                valueText: session.settings.density.formatted(
                    .percent.precision(.fractionLength(0)))
            )
            AsciiSliderRow(
                title: "对比度",
                value: $session.settings.contrast,
                range: 0.4...2,
                step: 0.05,
                valueText: session.settings.contrast.formatted(
                    .number.precision(.fractionLength(2)))
            )

            Toggle("反色", isOn: $session.settings.isInverted)
            Toggle("透明背景", isOn: $session.settings.hasTransparentBackground)
        }
    }

    private var animationControls: some View {
        VStack(alignment: .leading, spacing: DesignMetrics.space12) {
            Text("动画")
                .font(DesignTypography.sectionTitle)

            AsciiSliderRow(
                title: "动画强度",
                value: $session.settings.animationStrength,
                range: 0...1,
                step: 0.01,
                valueText: session.settings.animationStrength.formatted(
                    .percent.precision(.fractionLength(0))
                )
            )
            .disabled(session.settings.animation == .off)
        }
    }
}
