import SwiftUI

/// SwiftUI implementation of BoardUI's single-thumb slider presentation and interaction.
public struct ToolSlider: View {
    private let title: LocalizedStringKey
    @Binding private var value: Double
    private let scale: ToolSliderScale
    private let onEditingChanged: (Bool) -> Void

    @Environment(\.designPalette) private var palette
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.oneBoxAccessibilityReduceMotionOverride) private var reduceMotionOverride
    @State private var isDragging = false
    @State private var isTrackHovered = false
    @State private var isThumbHovered = false
    @State private var isPointerFocused = false
    @FocusState private var isFocused: Bool

    public init(
        _ title: LocalizedStringKey,
        value: Binding<Double>,
        in bounds: ClosedRange<Double>,
        step: Double? = nil,
        onEditingChanged: @escaping (Bool) -> Void = { _ in }
    ) {
        self.title = title
        _value = value
        scale = ToolSliderScale(bounds: bounds, step: step)
        self.onEditingChanged = onEditingChanged
    }

    public var body: some View {
        GeometryReader { geometry in
            let position = scale.fraction(for: value) * geometry.size.width
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(
                        (isTrackHovered ? palette.sliderTrackHover : palette.sliderTrack)
                            .shadow(.inner(color: palette.sliderInsetShadow, radius: 1, y: 1))
                    )
                    .frame(height: 6)
                    .animation(controlAnimation, value: isTrackHovered)
                Capsule()
                    .fill(
                        fillGradient.shadow(
                            .inner(color: palette.controlHighlight, radius: 0, y: 1)
                        )
                    )
                    .frame(width: position, height: 6)
                    .shadow(color: palette.sliderFillShadow, radius: 2, y: 1)
                thumb
                    .position(x: position, y: 16)
            }
            .frame(maxWidth: .infinity, minHeight: 32, maxHeight: 32)
            .contentShape(.rect)
            .onHover { isTrackHovered = $0 }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        guard isEnabled else { return }
                        if !isDragging {
                            isPointerFocused = true
                            isFocused = true
                            isDragging = true
                            onEditingChanged(true)
                        }
                        value = scale.value(at: gesture.location.x, width: geometry.size.width)
                    }
                    .onEnded { gesture in
                        if isDragging, isEnabled {
                            value = scale.value(at: gesture.location.x, width: geometry.size.width)
                        }
                        endDragging()
                    }
            )
        }
        .frame(height: 32)
        .opacity(isEnabled ? 1 : 0.5)
        .focusable(isEnabled)
        .focused($isFocused)
        .focusEffectDisabled()
        .onKeyPress(.leftArrow) { adjust(by: -1) }
        .onKeyPress(.downArrow) { adjust(by: -1) }
        .onKeyPress(.rightArrow) { adjust(by: 1) }
        .onKeyPress(.upArrow) { adjust(by: 1) }
        .onKeyPress(.pageDown) { adjust(by: -10) }
        .onKeyPress(.pageUp) { adjust(by: 10) }
        .onKeyPress(.home) { selectBoundary(scale.bounds.lowerBound) }
        .onKeyPress(.end) { selectBoundary(scale.bounds.upperBound) }
        .onChange(of: isFocused) { _, focused in
            if !focused { isPointerFocused = false }
        }
        .onChange(of: isEnabled) { _, enabled in
            if !enabled { endDragging() }
        }
        .onDisappear(perform: endDragging)
        .accessibilityRepresentation { accessibleSlider }
    }

    private var fillGradient: LinearGradient {
        LinearGradient(
            colors: [palette.primaryGradientStart, palette.primaryGradientEnd],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private var thumb: some View {
        Circle()
            .fill(
                palette.surface.shadow(
                    .inner(color: palette.sliderThumbHighlight, radius: 0, y: 1)
                )
            )
            .overlay {
                Circle().strokeBorder(
                    isDragging
                        ? palette.accent
                        : (isThumbHovered ? palette.sliderTrackHover : palette.border),
                    lineWidth: 1
                )
            }
            .overlay {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [palette.primaryGradientStart, palette.primaryGradientEnd],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .shadow(.inner(color: palette.controlHighlight, radius: 0, y: 1))
                    )
                    .frame(width: 8, height: 8)
                    .brightness(isDragging || isFocused ? 0.1 : 0)
            }
            .frame(width: 20, height: 20)
            .shadow(
                color: isDragging ? palette.sliderDragShadow : palette.sliderThumbShadow,
                radius: isDragging ? 8 : 4,
                y: isDragging ? 3 : 2
            )
            .overlay {
                if isFocused, !isPointerFocused {
                    Circle()
                        .stroke(palette.focusRing, lineWidth: 2)
                        .frame(width: 28, height: 28)
                }
            }
            .scaleEffect(isDragging ? 1.1 : (isThumbHovered ? 1.05 : 1))
            .animation(controlAnimation, value: isDragging)
            .animation(controlAnimation, value: isThumbHovered)
            .onHover { isThumbHovered = isEnabled && $0 }
    }

    private var controlAnimation: Animation? {
        (reduceMotionOverride ?? systemReduceMotion)
            ? nil : .timingCurve(0.25, 0.1, 0.25, 1, duration: 0.15)
    }

    @ViewBuilder
    private var accessibleSlider: some View {
        if let step = scale.step {
            Slider(value: accessibleValue, in: scale.bounds, step: step) { Text(title) }
                .labelsHidden()
        } else {
            Slider(value: accessibleValue, in: scale.bounds) { Text(title) }
                .labelsHidden()
        }
    }

    private var accessibleValue: Binding<Double> {
        Binding(
            get: { value },
            set: { newValue in
                guard isEnabled else { return }
                onEditingChanged(true)
                value = scale.snapped(newValue)
                onEditingChanged(false)
            }
        )
    }

    private func adjust(by increments: Double) -> KeyPress.Result {
        guard isEnabled else { return .ignored }
        isPointerFocused = false
        onEditingChanged(true)
        value = scale.adjusting(value, by: increments)
        onEditingChanged(false)
        return .handled
    }

    private func selectBoundary(_ newValue: Double) -> KeyPress.Result {
        guard isEnabled else { return .ignored }
        isPointerFocused = false
        onEditingChanged(true)
        value = newValue
        onEditingChanged(false)
        return .handled
    }

    private func endDragging() {
        guard isDragging else { return }
        isDragging = false
        onEditingChanged(false)
    }
}

struct ToolSliderScale {
    let bounds: ClosedRange<Double>
    let step: Double?

    func fraction(for value: Double) -> Double {
        guard bounds.upperBound > bounds.lowerBound else { return 0 }
        return (clamped(value) - bounds.lowerBound) / (bounds.upperBound - bounds.lowerBound)
    }

    func value(at position: CGFloat, width: CGFloat) -> Double {
        guard width > 0 else { return bounds.lowerBound }
        let fraction = min(max(Double(position / width), 0), 1)
        return snapped(bounds.lowerBound + fraction * (bounds.upperBound - bounds.lowerBound))
    }

    func adjusting(_ value: Double, by increments: Double) -> Double {
        snapped(value + increments * (step ?? (bounds.upperBound - bounds.lowerBound) / 100))
    }

    func snapped(_ value: Double) -> Double {
        guard let step else { return clamped(value) }
        return clamped(bounds.lowerBound + ((value - bounds.lowerBound) / step).rounded() * step)
    }

    private func clamped(_ value: Double) -> Double {
        min(max(value, bounds.lowerBound), bounds.upperBound)
    }
}
