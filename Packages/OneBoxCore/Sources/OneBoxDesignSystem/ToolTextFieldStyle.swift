import SwiftUI

/// BoardUI Input's neutral inset surface around native SwiftUI editing.
public struct ToolTextFieldStyle: TextFieldStyle {
    @Environment(\.designPalette) private var palette
    @Environment(\.isEnabled) private var isEnabled
    @FocusState private var isFocused: Bool
    @State private var isHovered = false
    private let systemImage: String?

    public init(systemImage: String? = nil) { self.systemImage = systemImage }

    public func _body(configuration: TextField<Self._Label>) -> some View {
        HStack(spacing: 8) {
            if let systemImage {
                Image(systemName: systemImage).foregroundStyle(palette.textSecondary)
                    .accessibilityHidden(true)
            }
            configuration.textFieldStyle(.plain).focused($isFocused)
        }
        .padding(.horizontal, 8)
        .frame(minHeight: 36)
        .background(palette.border, in: .rect(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10).strokeBorder(
                !isEnabled
                    ? .clear
                    : (isFocused
                        ? palette.borderActive : (isHovered ? palette.borderHover : .clear)),
                lineWidth: 2)
        }
        .animation(DesignMotion.hover, value: isHovered)
        .onHover { isHovered = $0 }
    }
}

/// A native text field with a drawn placeholder; AppKit's default placeholder color ignores SwiftUI prompt styling.
public struct ToolTextField: View {
    private let title: LocalizedStringKey
    @Binding private var text: String
    private let systemImage: String?
    private let externalFocus: FocusState<Bool>.Binding?
    @Environment(\.designPalette) private var palette
    @Environment(\.font) private var inheritedFont
    @Environment(\.isEnabled) private var isEnabled
    @FocusState private var localFocus: Bool
    @State private var isHovered = false

    public init(
        _ title: LocalizedStringKey, text: Binding<String>, systemImage: String? = nil,
        focus: FocusState<Bool>.Binding? = nil
    ) {
        self.title = title
        _text = text
        self.systemImage = systemImage
        self.externalFocus = focus
    }

    private var focus: FocusState<Bool>.Binding { externalFocus ?? $localFocus }
    private var isFocused: Bool { externalFocus?.wrappedValue ?? localFocus }

    public var body: some View {
        HStack(spacing: 8) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(palette.textSecondary)
                    .accessibilityHidden(true)
            }
            ZStack(alignment: .leading) {
                if text.isEmpty {
                    Text(title)
                        .foregroundStyle(
                            !isEnabled
                                ? palette.textDisabled
                                : (isFocused ? palette.textPrimary : palette.textSecondary)
                        )
                        .lineLimit(1)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                TextField("", text: $text)
                    .textFieldStyle(.plain)
                    .focused(focus)
                    .foregroundStyle(isEnabled ? palette.textPrimary : palette.textDisabled)
                    .accessibilityLabel(title)
            }
        }
        .font(inheritedFont ?? DesignTypography.body)
        .padding(.horizontal, 12)
        .frame(minHeight: 36)
        .background(palette.border, in: .rect(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10).strokeBorder(
                !isEnabled
                    ? .clear
                    : (isFocused
                        ? palette.borderActive : (isHovered ? palette.borderHover : .clear)),
                lineWidth: 2)
        }
        .contentShape(.rect(cornerRadius: 10))
        .onTapGesture { focus.wrappedValue = true }
        .onHover { isHovered = $0 }
        .animation(DesignMotion.hover, value: isHovered)
    }
}
