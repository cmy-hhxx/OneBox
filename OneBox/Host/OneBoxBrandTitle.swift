import OneBoxDesignSystem
import SwiftUI

struct OneBoxBrandTitle: View {
    @Environment(\.designPalette) private var palette

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text("One")
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            palette.brandGradientStart,
                            palette.brandGradientMiddle,
                            palette.brandGradientEnd,
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )

            Text("Box")
                .foregroundStyle(palette.textPrimary)
        }
        .font(DesignTypography.sidebarTitle)
        .lineLimit(1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("OneBox")
        .accessibilityAddTraits(.isHeader)
    }
}
