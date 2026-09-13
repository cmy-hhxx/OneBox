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
            .contentShape(.rect)
        }
        .buttonStyle(SidebarSelectionStyle(isSelected: isSelected))
        .accessibilityLabel(registration.displayName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct SidebarSelectionStyle: ButtonStyle {
    let isSelected: Bool
    @Environment(\.designPalette) private var palette

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                isSelected || configuration.isPressed ? palette.selection : .clear,
                in: .rect(cornerRadius: DesignMetrics.cornerRadius)
            )
    }
}
