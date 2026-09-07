import OSLog
import SwiftUI

private enum ToolInspectorPerformance {
    static let signposter = OSSignposter(
        subsystem: "com.cmy.OneBox",
        category: "Host"
    )
}

/// The two inspector widths supported by OneBox.
public enum ToolInspectorWidthPolicy: Equatable, Sendable {
    case standard
    case queue

    public var minimum: CGFloat {
        switch self {
        case .standard:
            DesignMetrics.inspectorWidth
        case .queue:
            280
        }
    }

    public var ideal: CGFloat {
        switch self {
        case .standard:
            DesignMetrics.inspectorWidth
        case .queue:
            320
        }
    }

    public var maximum: CGFloat {
        switch self {
        case .standard:
            DesignMetrics.inspectorWidth
        case .queue:
            360
        }
    }
}

/// Shared content chrome used by OneBox's native trailing inspectors.
@MainActor
private struct ToolInspectorContent<Content: View>: View {
    private let title: LocalizedStringKey
    private let closeLabel: LocalizedStringKey
    private let close: () -> Void
    private let onPresented: () -> Void
    private let content: Content

    @Environment(\.designPalette) private var palette

    init(
        _ title: LocalizedStringKey,
        closeLabel: LocalizedStringKey,
        close: @escaping () -> Void,
        onPresented: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.closeLabel = closeLabel
        self.close = close
        self.onPresented = onPresented
        self.content = content()
    }

    var body: some View {
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
        }
        .font(DesignTypography.body)
        .foregroundStyle(palette.textPrimary)
        .padding(DesignMetrics.space16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
        .accessibilityAction(.escape, close)
        .onExitCommand(perform: close)
        .onAppear(perform: onPresented)
    }
}

@MainActor
private struct ToolInspectorPresentationModifier<InspectorContent: View>: ViewModifier {
    @Binding private var isPresented: Bool

    private let title: LocalizedStringKey
    private let closeLabel: LocalizedStringKey
    private let widthPolicy: ToolInspectorWidthPolicy
    private let onDismiss: () -> Void
    private let inspectorContent: () -> InspectorContent
    @State private var hasInstalledNativeInspector: Bool
    @State private var presentationInterval: OSSignpostIntervalState?

    init(
        isPresented: Binding<Bool>,
        title: LocalizedStringKey,
        closeLabel: LocalizedStringKey,
        widthPolicy: ToolInspectorWidthPolicy,
        onDismiss: @escaping () -> Void,
        @ViewBuilder inspectorContent: @escaping () -> InspectorContent
    ) {
        _isPresented = isPresented
        _hasInstalledNativeInspector = State(initialValue: false)
        self.title = title
        self.closeLabel = closeLabel
        self.widthPolicy = widthPolicy
        self.onDismiss = onDismiss
        self.inspectorContent = inspectorContent
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        HStack(spacing: 0) {
            // The workspace is always the first child of this stable layout,
            // so installing the inspector never recreates stateful content
            // such as an MTKView or a focused editor.
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if hasInstalledNativeInspector {
                Color.clear
                    .frame(width: 0)
                    .accessibilityHidden(true)
                    .inspector(isPresented: $isPresented) {
                        ToolInspectorContent(
                            title,
                            closeLabel: closeLabel,
                            close: dismiss,
                            onPresented: finishPresentationInterval
                        ) {
                            inspectorContent()
                        }
                        .inspectorColumnWidth(
                            min: widthPolicy.minimum,
                            ideal: widthPolicy.ideal,
                            max: widthPolicy.maximum
                        )
                    }
                    .frame(
                        minWidth: isPresented ? widthPolicy.minimum : 0,
                        idealWidth: isPresented ? widthPolicy.ideal : 0,
                        maxWidth: isPresented ? widthPolicy.maximum : 0
                    )
            }
        }
        .onAppear(perform: installInitiallyPresentedInspectorIfNeeded)
        .onChange(of: isPresented) { wasPresented, isPresented in
            if !wasPresented, isPresented {
                hasInstalledNativeInspector = true
                beginPresentationInterval()
                return
            }
            guard wasPresented, !isPresented else { return }
            cancelPresentationInterval()
            onDismiss()
        }
        .onDisappear {
            cancelPresentationInterval()
        }
    }

    private func installInitiallyPresentedInspectorIfNeeded() {
        guard isPresented, !hasInstalledNativeInspector else { return }
        beginPresentationInterval()
        hasInstalledNativeInspector = true
    }

    private func beginPresentationInterval() {
        cancelPresentationInterval()
        presentationInterval = ToolInspectorPerformance.signposter.beginInterval(
            "InspectorPresentation"
        )
    }

    private func finishPresentationInterval() {
        guard let presentationInterval else { return }
        self.presentationInterval = nil
        ToolInspectorPerformance.signposter.endInterval(
            "InspectorPresentation",
            presentationInterval
        )
    }

    private func cancelPresentationInterval() {
        guard let presentationInterval else { return }
        self.presentationInterval = nil
        ToolInspectorPerformance.signposter.endInterval(
            "InspectorPresentation",
            presentationInterval,
            "cancelled"
        )
    }

    private func dismiss() {
        isPresented = false
    }
}

extension View {
    /// Presents a native macOS trailing inspector with OneBox's shared content chrome.
    @MainActor
    public func toolInspector<InspectorContent: View>(
        isPresented: Binding<Bool>,
        title: LocalizedStringKey,
        closeLabel: LocalizedStringKey,
        widthPolicy: ToolInspectorWidthPolicy = .standard,
        onDismiss: @escaping () -> Void = {},
        @ViewBuilder content: @escaping () -> InspectorContent
    ) -> some View {
        modifier(
            ToolInspectorPresentationModifier(
                isPresented: isPresented,
                title: title,
                closeLabel: closeLabel,
                widthPolicy: widthPolicy,
                onDismiss: onDismiss,
                inspectorContent: content
            )
        )
    }
}
