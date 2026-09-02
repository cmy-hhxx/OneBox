import SwiftUI

/// Shared right-side inspector chrome for every OneBox tool.
///
/// The host owns presentation and placement; this view owns the panel's
/// consistent title bar, one scrolling content region, Escape behavior, and
/// accessibility semantics.
@MainActor
public struct ToolInspectorPanel<Content: View>: View {
    private let title: LocalizedStringKey
    private let closeLabel: LocalizedStringKey
    private let close: () -> Void
    private let content: Content

    @Environment(\.designPalette) private var palette

    public init(
        _ title: LocalizedStringKey,
        closeLabel: LocalizedStringKey,
        close: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.closeLabel = closeLabel
        self.close = close
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: DesignMetrics.space12) {
            HStack {
                Text(title)
                    .font(DesignTypography.sectionTitle)
                    .foregroundStyle(palette.textPrimary)

                Spacer(minLength: 0)

                Button(closeLabel, systemImage: "xmark", action: close)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .keyboardShortcut(.cancelAction)
                    .frame(
                        width: DesignMetrics.space24,
                        height: DesignMetrics.space24
                    )
                    .accessibilityLabel(closeLabel)
            }

            ScrollView {
                content
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
        }
        .font(DesignTypography.body)
        .foregroundStyle(palette.textPrimary)
        .padding(DesignMetrics.space16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(palette.surface)
        .clipShape(.rect(cornerRadius: DesignMetrics.cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: DesignMetrics.cornerRadius)
                .stroke(palette.border, lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
        .accessibilityAction(.escape, close)
        .onExitCommand(perform: close)
    }
}
