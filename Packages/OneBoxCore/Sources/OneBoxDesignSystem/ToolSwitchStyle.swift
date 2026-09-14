import SwiftUI

/// BoardUI medium pill switch: 42×24 track, 18pt thumb, embossed 7.5pt center chip.
public struct ToolSwitchStyle: ToggleStyle {
    private let showsLabel: Bool
    @Environment(\.designPalette) private var palette
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.oneBoxAccessibilityReduceMotionOverride) private var reduceMotionOverride

    public init(showsLabel: Bool = true) { self.showsLabel = showsLabel }

    public func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: DesignMetrics.space12) {
            if showsLabel {
                configuration.label
                    .font(DesignTypography.body)
                    .foregroundStyle(isEnabled ? palette.textPrimary : palette.textDisabled)
                Spacer(minLength: 0)
            }
            Button {
                configuration.isOn.toggle()
            } label: {
                ZStack {
                    Capsule().fill(
                        configuration.isOn
                            ? AnyShapeStyle(
                                LinearGradient(
                                    colors: [palette.accent, palette.accentPressed],
                                    startPoint: .top, endPoint: .bottom))
                            : AnyShapeStyle(palette.toggleTrack)
                    )
                    .overlay {
                        if configuration.isOn {
                            Capsule().strokeBorder(palette.controlHighlight, lineWidth: 0.75)
                        }
                    }
                    Circle()
                        .fill(
                            LinearGradient(
                                stops: [
                                    .init(color: palette.controlIndicator, location: 0.43837),
                                    .init(color: palette.controlIndicatorSubtle, location: 1),
                                ], startPoint: .top, endPoint: .bottom)
                        )
                        .frame(width: 18, height: 18)
                        .overlay {
                            Circle().fill(
                                LinearGradient(
                                    colors: configuration.isOn
                                        ? [palette.switchChipEnd, palette.switchChipStart]
                                        : [
                                            palette.controlIndicatorSubtle,
                                            palette.controlIndicator,
                                        ],
                                    startPoint: .top, endPoint: .bottom)
                            )
                            .overlay {
                                Circle().strokeBorder(
                                    configuration.isOn ? palette.accentPressed : palette.border,
                                    lineWidth: 0.375)
                            }
                            .frame(width: 7.5, height: 7.5)
                        }
                        .shadow(color: palette.controlShadow, radius: 3, x: 0, y: 0.75)
                        .offset(x: configuration.isOn ? 9 : -9)
                }
                .opacity(isEnabled ? 1 : 0.5)
                .frame(width: 42, height: 24)
                .contentShape(.capsule)
                .animation(
                    (reduceMotionOverride ?? systemReduceMotion) ? nil : DesignMotion.selection,
                    value: configuration.isOn)
            }
            .buttonStyle(.plain)
        }
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }.toggleStyle(.switch)
        }
    }
}
