import OneBoxDesignSystem
import OneBoxRuntime
import SwiftUI

struct HostSidebarRow: View {
    let registration: ToolRegistration
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.designPalette) private var palette

    var body: some View {
        Button(action: action) {
            HStack {
                Text(registration.displayName)
                    .font(DesignTypography.bodyMedium)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, DesignMetrics.sidebarTextInset)
            .frame(maxWidth: .infinity, minHeight: DesignMetrics.sidebarRowHeight)
            .background(isSelected ? palette.selection : .clear)
            .clipShape(.rect(cornerRadius: DesignMetrics.cornerRadius))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(registration.displayName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
