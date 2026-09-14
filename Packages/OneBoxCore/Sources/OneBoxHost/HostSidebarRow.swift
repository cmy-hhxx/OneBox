import OneBoxDesignSystem
import OneBoxRuntime
import SwiftUI

struct HostSidebarRow: View {
    let registration: ToolRegistration
    let isSelected: Bool
    var isCollapsed = false
    let action: () -> Void

    @Environment(\.designPalette) private var palette
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                SidebarSymbol(name: registration.systemImage)
                    .foregroundStyle(isSelected ? palette.controlIndicator : palette.textSecondary)
                    .frame(width: 36, height: DesignMetrics.sidebarRowHeight)
                SidebarLabelSlot(isCollapsed: isCollapsed) {
                    Text(registration.displayName)
                        .font(DesignTypography.bodyMedium)
                        .foregroundStyle(
                            isSelected ? palette.controlIndicator : palette.textSecondary)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: DesignMetrics.sidebarRowHeight)
            .contentShape(.rect)
        }
        .buttonStyle(SidebarSelectionStyle(isSelected: isSelected, isHovered: isHovered))
        .onHover { isHovered = $0 }
        .help(registration.displayName)
        .accessibilityLabel(registration.displayName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// BoardUI clips an intrinsic, single-line label; it never lays text out at the rail's narrow width.
struct SidebarLabelSlot<Content: View>: View {
    let isCollapsed: Bool
    @ViewBuilder let content: Content

    var body: some View {
        Color.clear
            .overlay(alignment: .leading) {
                content
                    .fixedSize(horizontal: true, vertical: false)
                    .opacity(isCollapsed ? 0 : 1)
                    .blur(radius: isCollapsed ? 3 : 0)
            }
            .clipped()
            .accessibilityHidden(isCollapsed)
    }
}

private struct SidebarSelectionStyle: ButtonStyle {
    let isSelected: Bool
    let isHovered: Bool
    @Environment(\.designPalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.oneBoxAccessibilityReduceMotionOverride) private var reduceMotionOverride

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                RoundedRectangle(cornerRadius: 10)
                    .fill(
                        isSelected
                            ? AnyShapeStyle(
                                LinearGradient(
                                    colors: [palette.accent, palette.accentPressed],
                                    startPoint: .top, endPoint: .bottom))
                            : AnyShapeStyle(
                                configuration.isPressed || isHovered ? palette.border : .clear)
                    )
                    .overlay {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 10).strokeBorder(
                                palette.controlHighlight, lineWidth: 1)
                        }
                    }
            }
            .animation(
                (reduceMotionOverride ?? reduceMotion) ? nil : DesignMotion.hover, value: isHovered)
    }
}
