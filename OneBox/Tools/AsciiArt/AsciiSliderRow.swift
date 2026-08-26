import OneBoxDesignSystem
import SwiftUI

@MainActor
struct AsciiSliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let valueText: String

    @Environment(\.designPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: DesignMetrics.space4) {
            HStack {
                Text(title)
                Spacer(minLength: 0)
                Text(valueText)
                    .foregroundStyle(palette.textSecondary)
                    .monospacedDigit()
            }
            .font(DesignTypography.body)

            Slider(value: $value, in: range, step: step)
                .accessibilityLabel(title)
                .accessibilityValue(valueText)
        }
    }
}
