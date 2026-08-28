import OneBoxDesignSystem
import SwiftUI

struct PodPinSettingsView: View {
    @ObservedObject var preferences: AppPreferences
    let onSetPlaybackRate: @MainActor @Sendable (Double) -> Void

    @Environment(\.designPalette) private var palette

    var body: some View {
        ScrollView {
            playbackSection
                .padding(.vertical, DesignMetrics.space8)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(palette.background)
        .tint(palette.accent)
    }

    private var playbackSection: some View {
        PodPinSettingsSection("播放体验") {
            PodPinSettingsSliderRow(
                title: "封面显示强度",
                detail: "调整正在播放页的封面强度。文字和控件始终保持清晰。",
                value: $preferences.nowPlayingContentOpacity,
                range: AppPreferences.nowPlayingContentOpacityRange,
                step: 0.05,
                accessibilityIdentifier: "settings.now-playing.content-opacity"
            )

            sectionDivider

            VStack(alignment: .leading, spacing: DesignMetrics.space12) {
                PodPinSettingsLabel(
                    title: "播放速度",
                    detail: "立即应用到当前播放，并用于之后的内容。"
                )

                Picker("播放速度", selection: playbackRateBinding) {
                    ForEach(AppPreferences.supportedPlaybackRates, id: \.self) { rate in
                        Text(playbackRateLabel(rate)).tag(rate)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .controlSize(.regular)
                .accessibilityLabel("播放速度")
                .accessibilityValue(playbackRateLabel(preferences.playbackRate))
            }
        }
    }

    private var sectionDivider: some View {
        Rectangle()
            .fill(palette.border)
            .frame(height: 1)
            .accessibilityHidden(true)
    }

    private var playbackRateBinding: Binding<Double> {
        Binding(get: { preferences.playbackRate }, set: { onSetPlaybackRate($0) })
    }

    private func playbackRateLabel(_ rate: Double) -> String {
        "\(rate.formatted(.number.precision(.fractionLength(0...2))))×"
    }
}

private struct PodPinSettingsSection<Content: View>: View {
    let title: String
    let content: Content

    @Environment(\.designPalette) private var palette

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignMetrics.space12) {
            Text(title)
                .font(DesignTypography.sectionTitle)
                .foregroundStyle(palette.textPrimary)

            VStack(alignment: .leading, spacing: DesignMetrics.space16) {
                content
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct PodPinSettingsLabel: View {
    let title: String
    let detail: String

    @Environment(\.designPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: DesignMetrics.space4) {
            Text(title)
                .font(DesignTypography.bodyMedium)
                .foregroundStyle(palette.textPrimary)

            Text(detail)
                .font(DesignTypography.metadata)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct PodPinSettingsSliderRow: View {
    let title: String
    let detail: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let accessibilityIdentifier: String

    @Environment(\.designPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: DesignMetrics.space12) {
            PodPinSettingsLabel(title: title, detail: detail)

            HStack(spacing: DesignMetrics.space12) {
                Slider(value: $value, in: range, step: step)
                    .controlSize(.regular)
                    .accessibilityLabel(title)
                    .accessibilityHint(detail)

                Text(value, format: .percent.precision(.fractionLength(0)))
                    .font(DesignTypography.metadata)
                    .monospacedDigit()
                    .foregroundStyle(palette.textSecondary)
                    .frame(minWidth: 44, alignment: .trailing)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}
