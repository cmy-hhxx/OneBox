import OneBoxDesignSystem
import SwiftUI

struct OneBoxBrandTitle: View {
    @Environment(\.designPalette) private var palette

    var body: some View {
        HStack(spacing: DesignMetrics.space8) {
            OneBoxBrandMark()

            Text("OneBox")
                .font(DesignTypography.sidebarTitle)
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("OneBox")
        .accessibilityAddTraits(.isHeader)
    }
}
