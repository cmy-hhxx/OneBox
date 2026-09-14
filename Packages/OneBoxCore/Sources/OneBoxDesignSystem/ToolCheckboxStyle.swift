import SwiftUI

/// BoardUI's 16pt checkbox glyph with its 200ms path-draw check animation.
public struct ToolCheckboxStyle: ToggleStyle {
    @Environment(\.designPalette) private var palette
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.oneBoxAccessibilityReduceMotionOverride) private var reduceMotionOverride
    @State private var isHovered = false

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(
                        configuration.isOn
                            ? AnyShapeStyle(
                                LinearGradient(
                                    colors: isHovered
                                        ? [palette.accentHover, palette.accent]
                                        : [palette.accent, palette.accentPressed], startPoint: .top,
                                    endPoint: .bottom))
                            : AnyShapeStyle(palette.surface)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 4).strokeBorder(
                            configuration.isOn
                                ? palette.controlHighlight
                                : (isHovered ? palette.borderActive : palette.borderHover),
                            lineWidth: 1)
                    }
                    .overlay {
                        BoardCheckmark().trim(from: 0, to: configuration.isOn ? 1 : 0)
                            .stroke(
                                palette.controlIndicator,
                                style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                            )
                            .animation(
                                (reduceMotionOverride ?? systemReduceMotion)
                                    ? nil : .timingCurve(0.65, 0, 0.35, 1, duration: 0.2),
                                value: configuration.isOn)
                    }
                    .shadow(color: palette.controlShadow, radius: 2, x: 0, y: 1)
                    .frame(width: 16, height: 16)
                configuration.label.font(DesignTypography.bodyMedium).foregroundStyle(
                    palette.textPrimary)
            }
            .opacity(isEnabled ? 1 : 0.5)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .animation(
            (reduceMotionOverride ?? systemReduceMotion) ? nil : DesignMotion.hover,
            value: isHovered
        )
        .onHover { isHovered = $0 }
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }.toggleStyle(.checkbox)
        }
    }
}

private struct BoardCheckmark: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x / 16 * rect.width, y: rect.minY + y / 16 * rect.height)
        }
        path.move(to: point(4, 7.7002))
        path.addLine(to: point(6.64645, 10.3466))
        path.addCurve(
            to: point(7.35355, 10.3466), control1: point(6.84171, 10.5419),
            control2: point(7.15829, 10.5419))
        path.addLine(to: point(12, 5.7002))
        return path
    }
}
