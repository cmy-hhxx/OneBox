import OneBoxDesignSystem
import SwiftUI

@MainActor
struct AsciiSliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double? = nil
    let valueText: String

    @Environment(\.designPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: DesignMetrics.space8) {
            HStack {
                Text(title)
                Spacer(minLength: 0)
                Text(valueText)
                    .font(DesignTypography.metadata)
                    .foregroundStyle(palette.textPrimary)
                    .monospacedDigit()
                    .frame(minWidth: 48, alignment: .trailing)
            }
            .font(DesignTypography.body)

            ToolSlider(LocalizedStringKey(title), value: $value, in: range, step: step)
                .accessibilityValue(valueText)
        }
    }
}
