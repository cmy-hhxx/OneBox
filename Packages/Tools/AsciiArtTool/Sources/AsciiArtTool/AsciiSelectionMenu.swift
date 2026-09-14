import OneBoxDesignSystem
import SwiftUI

@MainActor
struct AsciiSelectionMenu<Value: Hashable>: View {
    let title: LocalizedStringKey
    let selectedTitle: String
    @Binding var selection: Value
    let options: [ToolSegment<Value>]

    @Environment(\.designPalette) private var palette

    var body: some View {
        Menu {
            Picker(title, selection: $selection) {
                ForEach(options) { option in
                    Text(option.title).tag(option.value)
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(selectedTitle)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.down")
                    .font(DesignTypography.metadata)
                    .foregroundStyle(palette.textSecondary)
                    .frame(width: 16, height: 16)
            }
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(ToolActionButtonStyle(kind: .secondary))
        .accessibilityLabel(title)
        .accessibilityValue(selectedTitle)
        .help(Text(title))
    }
}
