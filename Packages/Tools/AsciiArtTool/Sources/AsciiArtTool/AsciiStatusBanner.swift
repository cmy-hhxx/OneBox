import OneBoxDesignSystem
import SwiftUI

@MainActor
struct AsciiStatusBanner: View {
    let message: String

    @Environment(\.designPalette) private var palette

    var body: some View {
        Text(message)
            .font(DesignTypography.metadata)
            .foregroundStyle(palette.negative)
            .padding(.horizontal, DesignMetrics.space12)
            .frame(minHeight: 32)
            .background(palette.surface)
            .clipShape(.rect(cornerRadius: DesignMetrics.cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: DesignMetrics.cornerRadius)
                    .stroke(palette.negative, lineWidth: 1)
            }
            .accessibilityAddTraits(.updatesFrequently)
    }
}
