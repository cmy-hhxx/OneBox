import SwiftUI

/// Native BoardUI button, mapped from the installed registry's buttons/button.tsx and theme.css.
public struct ToolActionButtonStyle: ButtonStyle {
    public enum Kind: Sendable { case primary, secondary, quiet }
    private let kind: Kind
    private let compact: Bool
    @Environment(\.designPalette) private var palette
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.oneBoxAccessibilityReduceMotionOverride) private var reduceMotionOverride
    @State private var isHovered = false

    public init(kind: Kind = .secondary, compact: Bool = false) {
        self.kind = kind
        self.compact = compact
    }

    public func makeBody(configuration: Configuration) -> some View {
        let radius: CGFloat = compact ? 8 : 10
        configuration.label
            .font(DesignTypography.bodyMedium)
            .foregroundStyle(foreground(role: configuration.role))
            .padding(.horizontal, compact ? 10 : 12)
            .frame(minHeight: compact ? 32 : 36)
            .background {
                if kind == .primary, isEnabled {
                    RoundedRectangle(cornerRadius: radius)
                        .fill(
                            LinearGradient(
                                colors: [palette.primaryGradientStart, palette.primaryGradientEnd],
                                startPoint: .top, endPoint: .bottom)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: radius)
                                .fill(
                                    LinearGradient(
                                        colors: configuration.isPressed
                                            ? [palette.accentPressed, palette.accentDeep]
                                            : [palette.accentHover, palette.accent],
                                        startPoint: .top, endPoint: .bottom)
                                )
                                .opacity(isHovered || configuration.isPressed ? 1 : 0)
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: radius)
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [palette.controlHighlight, .clear],
                                        startPoint: .top, endPoint: .bottom), lineWidth: 1)
                        }
                } else {
                    RoundedRectangle(cornerRadius: radius).fill(
                        background(isPressed: configuration.isPressed))
                }
            }
            .overlay {
                if kind == .secondary {
                    RoundedRectangle(cornerRadius: radius).strokeBorder(
                        palette.border, lineWidth: 1)
                }
            }
            .shadow(
                color: kind == .primary && isEnabled ? palette.controlShadow : .clear,
                radius: 2, x: 0, y: 1
            )
            .animation(reducesMotion ? nil : DesignMotion.hover, value: configuration.isPressed)
            .scaleEffect(configuration.isPressed && isEnabled && !reducesMotion ? 0.98 : 1)
            .animation(
                reducesMotion ? nil : DesignMotion.press(configuration.isPressed),
                value: configuration.isPressed
            )
            .animation(reducesMotion ? nil : DesignMotion.hover, value: isHovered)
            .contentShape(.rect(cornerRadius: radius))
            .onHover { isHovered = $0 }
    }

    private var reducesMotion: Bool { reduceMotionOverride ?? systemReduceMotion }
    private func foreground(role: ButtonRole?) -> Color {
        guard isEnabled else { return palette.textDisabled }
        if role == .destructive, kind != .primary { return palette.negative }
        return kind == .primary ? palette.textOnAccent : palette.textPrimary
    }
    private func background(isPressed: Bool) -> Color {
        guard isEnabled else { return palette.surfaceElevated }
        switch kind {
        case .primary: return palette.accent
        case .secondary:
            return isPressed
                ? palette.border : (isHovered ? palette.surfaceElevated : palette.surface)
        case .quiet: return isPressed || isHovered ? palette.surfaceElevated : .clear
        }
    }
}

public struct ToolIconButtonStyle: ButtonStyle {
    private let isSelected: Bool
    @Environment(\.designPalette) private var palette
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.oneBoxAccessibilityReduceMotionOverride) private var reduceMotionOverride
    @State private var isHovered = false

    public init(isSelected: Bool = false) { self.isSelected = isSelected }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .regular))
            .foregroundStyle(
                !isEnabled
                    ? palette.textDisabled
                    : (isSelected ? palette.accentPressed : palette.textPrimary)
            )
            .frame(width: 32, height: 32)
            .background(
                configuration.isPressed && isEnabled
                    ? palette.border
                    : ((!isEnabled || isHovered || isSelected)
                        ? palette.surfaceElevated : palette.surface), in: .rect(cornerRadius: 10)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10).strokeBorder(
                    !isEnabled
                        ? palette.border
                        : (configuration.isPressed
                            ? palette.borderActive
                            : (isHovered ? palette.borderHover : palette.border)), lineWidth: 1)
            }
            .shadow(color: isEnabled ? palette.controlShadow : .clear, radius: 2, x: 0, y: 1)
            .opacity(isEnabled ? 1 : 0.6)
            .contentShape(.rect(cornerRadius: 10))
            .animation(
                (reduceMotionOverride ?? systemReduceMotion) ? nil : DesignMotion.hover,
                value: isHovered
            )
            .animation(
                (reduceMotionOverride ?? systemReduceMotion) ? nil : DesignMotion.hover,
                value: configuration.isPressed
            )
            .onHover { isHovered = $0 }
    }
}

public struct ToolCloseButtonStyle: ButtonStyle {
    @Environment(\.designPalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.oneBoxAccessibilityReduceMotionOverride) private var reduceMotionOverride
    @State private var isHovered = false
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.6, weight: .semibold))
            .foregroundStyle(isHovered ? palette.textPrimary : palette.textSecondary)
            .frame(width: 24, height: 24)
            .background(palette.border, in: .circle)
            .contentShape(.circle)
            .animation(
                (reduceMotionOverride ?? reduceMotion) ? nil : DesignMotion.hover, value: isHovered
            )
            .onHover { isHovered = $0 }
    }
}

public struct InspectorSection<Content: View>: View {
    private let title: LocalizedStringKey
    private let content: Content
    @Environment(\.designPalette) private var palette

    public init(title: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: DesignMetrics.space12) {
            Text(title).font(DesignTypography.sectionTitle)
                .foregroundStyle(palette.textPrimary).accessibilityAddTraits(.isHeader)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
