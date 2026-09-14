import OneBoxDesignSystem
import SwiftUI

struct SidebarToggleButton: View {
    let accessibilityTitle: String
    let action: () -> Void

    @Environment(\.designPalette) private var palette

    var body: some View {
        Button(action: action) {
            SidebarSymbol(name: "sidebar.left", size: 18)
        }
        .foregroundStyle(palette.textSecondary)
        .frame(
            width: DesignMetrics.titlebarControlSize,
            height: DesignMetrics.titlebarControlSize
        )
        .contentShape(.rect)
        .buttonStyle(ToolIconButtonStyle())
        .accessibilityLabel(accessibilityTitle)
        .accessibilityIdentifier("sidebar.left")
        .help(accessibilityTitle)
    }
}
