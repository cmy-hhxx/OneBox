import OneBoxDesignSystem
import SwiftUI

@MainActor
struct AsciiStatusBanner: View {
    let message: String
    let retry: (() -> Void)?

    @Environment(\.designPalette) private var palette

    var body: some View {
        HStack(spacing: DesignMetrics.space8) {
            Text(message)
                .font(DesignTypography.metadata)
                .foregroundStyle(palette.negative)

            if let retry {
                Button("重试", systemImage: "arrow.clockwise", action: retry)
                    .buttonStyle(.borderless)
                    .font(DesignTypography.metadata)
            }
        }
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
