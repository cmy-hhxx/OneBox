import OneBoxDesignSystem
import SwiftUI

struct SidebarToggleButton: View {
    let accessibilityTitle: String
    let action: () -> Void

    @Environment(\.designPalette) private var palette

    var body: some View {
        Button(accessibilityTitle, systemImage: "sidebar.left", action: action)
            .labelStyle(.iconOnly)
            .font(.system(size: 16, weight: .regular))
            .foregroundStyle(palette.textSecondary)
            .frame(
                width: DesignMetrics.titlebarControlSize,
                height: DesignMetrics.titlebarControlSize
            )
            .contentShape(.rect)
            .buttonStyle(.plain)
            .help(accessibilityTitle)
    }
}
