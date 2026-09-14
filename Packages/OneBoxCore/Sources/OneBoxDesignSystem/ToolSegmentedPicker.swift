import SwiftUI

public struct ToolSegment<Value: Hashable>: Identifiable {
    public let title: String
    public let value: Value
    public var id: Value { value }
    public init(_ title: String, value: Value) {
        self.title = title
        self.value = value
    }
}

/// BoardUI segmented control with a continuously moving white selection layer.
public struct ToolSegmentedPicker<Value: Hashable>: View {
    private let title: LocalizedStringKey
    @Binding private var selection: Value
    private let options: [ToolSegment<Value>]
    @Environment(\.designPalette) private var palette
    @Environment(\.isEnabled) private var isEnabled
    @FocusState private var focusedValue: Value?
    @Namespace private var selectionNamespace
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.oneBoxAccessibilityReduceMotionOverride) private var reduceMotionOverride

    public init(
        _ title: LocalizedStringKey, selection: Binding<Value>, options: [ToolSegment<Value>]
    ) {
        self.title = title
        _selection = selection
        self.options = options
    }

    public var body: some View {
        HStack(spacing: 2) {
            ForEach(options) { option in
                Button {
                    selection = option.value
                } label: {
                    Text(option.title)
                        .font(
                            selection == option.value
                                ? DesignTypography.bodyMedium : DesignTypography.body
                        )
                        .foregroundStyle(
                            !isEnabled
                                ? palette.textDisabled
                                : (selection == option.value
                                    ? palette.textPrimary : palette.textSecondary)
                        )
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .frame(maxWidth: .infinity, minHeight: 28)
                        .background {
                            if selection == option.value {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(palette.surface)
                                    .shadow(color: palette.controlShadow, radius: 0, x: 0, y: 1)
                                    .matchedGeometryEffect(id: "selection", in: selectionNamespace)
                            }
                        }
                        .contentShape(.rect(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .focused($focusedValue, equals: option.value)
                .accessibilityAddTraits(selection == option.value ? .isSelected : [])
            }
        }
        .padding(4)
        .background(palette.surfaceElevated, in: .rect(cornerRadius: 10))
        .animation(
            (reduceMotionOverride ?? systemReduceMotion) ? nil : DesignMotion.selection,
            value: selection
        )
        .onMoveCommand { direction in
            guard isEnabled, let index = options.firstIndex(where: { $0.value == selection }) else {
                return
            }
            let next: Int
            switch direction {
            case .left, .up: next = max(0, index - 1)
            case .right, .down: next = min(options.count - 1, index + 1)
            default: return
            }
            selection = options[next].value
            focusedValue = selection
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }
}
