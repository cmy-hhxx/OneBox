import OneBoxDesignSystem
import SwiftUI

@MainActor
struct AsciiBrandPlaceholder: View {
    @Environment(\.designPalette) private var palette

    var body: some View {
        ZStack {
            palette.background

            RoundedRectangle(cornerRadius: 28)
                .fill(palette.textPrimary)
                .frame(width: 152, height: 152)

            Text("00101\n01001\n10100\n01010\n10010")
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(palette.textSecondary)

            Text("1")
                .font(.system(size: 104, weight: .bold, design: .monospaced))
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            palette.brandGradientStart,
                            palette.brandGradientMiddle,
                            palette.brandGradientEnd,
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
    }
}
