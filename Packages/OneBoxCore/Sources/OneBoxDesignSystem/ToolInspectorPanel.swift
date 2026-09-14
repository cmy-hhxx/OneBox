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
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(title)
                    .font(DesignTypography.sectionTitle)
                    .foregroundStyle(palette.textPrimary)

                Spacer(minLength: 0)

                Button(closeLabel, systemImage: "xmark", action: close)
                    .labelStyle(.iconOnly)
                    .buttonStyle(ToolCloseButtonStyle())
                    .keyboardShortcut(.cancelAction)
                    .frame(
                        width: DesignMetrics.space24,
                        height: DesignMetrics.space24
                    )
                    .accessibilityLabel(closeLabel)
            }
            .padding(.horizontal, DesignMetrics.space16)
            .frame(height: DesignMetrics.inspectorHeaderHeight)

            Divider().overlay(palette.border)

            ScrollView {
                content
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(DesignMetrics.space16)
            }
        }
        .font(DesignTypography.body)
        .foregroundStyle(palette.textPrimary)
        .background(palette.surface)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
        .accessibilityAction(.escape, close)
        .onExitCommand(perform: close)
        .onAppear(perform: onPresented)
    }
}

nonisolated private struct ToolInspectorLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        if let width = proposal.width, width.isFinite,
            let height = proposal.height, height.isFinite
        {
            return CGSize(width: width, height: height)
        }
        let boundedProposal = ProposedViewSize(
            width: proposal.width.flatMap { $0.isFinite ? $0 : nil },
            height: proposal.height.flatMap { $0.isFinite ? $0 : nil })
        let sizes = subviews.map { $0.sizeThatFits(boundedProposal) }
        return CGSize(
            width: boundedProposal.width ?? sizes.reduce(0) { $0 + $1.width },
            height: boundedProposal.height ?? sizes.map(\.height).max() ?? 0)
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) {
        guard let primary = subviews.first else { return }
        let inspector = subviews.dropFirst().first
        let inspectorWidth = min(
            bounds.width,
            inspector?.sizeThatFits(ProposedViewSize(bounds.size)).width ?? 0)
        // Only the native pane negotiates its width. The expensive workspace receives
        // one concrete proposal instead of HStack's minimum/maximum/alignment probes.
        let primaryProposal = ProposedViewSize(
            width: bounds.width - inspectorWidth, height: bounds.height)
        _ = primary.sizeThatFits(primaryProposal)
        primary.place(at: bounds.origin, proposal: primaryProposal)
        inspector?.place(
            at: CGPoint(x: bounds.maxX - inspectorWidth, y: bounds.minY),
            proposal: ProposedViewSize(width: inspectorWidth, height: bounds.height))
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
    @State private var isNativePresented = false
    @State private var hasMountedNativeInspector = false
    @State private var presentationGeneration = 0
    @State private var acceptsNativeDismissal = false
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.oneBoxAccessibilityReduceMotionOverride) private var reduceMotionOverride
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
        ToolInspectorLayout {
            // The workspace is always the first child of this stable layout,
            // so installing the inspector never recreates stateful content
            // such as an MTKView or a focused editor.
            content
                .padding(.trailing, isNativePresented ? DesignMetrics.inspectorGutter : 0)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if hasInstalledNativeInspector {
                Color.clear
                    .frame(width: 0)
                    .accessibilityHidden(true)
                    .inspector(isPresented: nativePresentation) {
                        ToolInspectorContent(
                            title,
                            closeLabel: closeLabel,
                            close: dismiss,
                            onPresented: finishPresentationInterval
                        ) {
                            inspectorContent()
                        }
                        .transaction { $0.animation = nil }
                        .inspectorColumnWidth(
                            min: widthPolicy.minimum,
                            ideal: widthPolicy.ideal,
                            max: widthPolicy.maximum
                        )
                    }
                    .frame(
                        minWidth: isNativePresented ? widthPolicy.minimum : 0,
                        idealWidth: isNativePresented ? widthPolicy.ideal : 0,
                        maxWidth: isNativePresented ? widthPolicy.maximum : 0
                    )
                    .task {
                        // Only first installation needs a closed layout pass. Later requests
                        // synchronize immediately instead of leaving two bindings out of sync.
                        await Task.yield()
                        guard !Task.isCancelled else { return }
                        hasMountedNativeInspector = true
                        updateNativePresentation(isPresented)
                    }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear(perform: installInitiallyPresentedInspectorIfNeeded)
        .onChange(of: isPresented) { wasPresented, isPresented in
            if !wasPresented, isPresented {
                beginPresentationInterval()
                if hasMountedNativeInspector {
                    updateNativePresentation(true)
                } else {
                    hasInstalledNativeInspector = true
                }
                return
            }
            guard wasPresented, !isPresented else { return }
            updateNativePresentation(false)
            cancelPresentationInterval()
            onDismiss()
        }
        .onDisappear {
            presentationGeneration += 1
            acceptsNativeDismissal = false
            cancelPresentationInterval()
        }
    }

    private var reducesMotion: Bool { reduceMotionOverride ?? systemReduceMotion }

    private var nativePresentation: Binding<Bool> {
        Binding(
            get: { isNativePresented },
            set: { presented in
                // Native animation acknowledgements can arrive after a reversed request.
                // App buttons/Escape own requests; accept native dismissals only once settled.
                guard !presented, acceptsNativeDismissal, isPresented else { return }
                isPresented = false
            })
    }

    private func updateNativePresentation(_ presented: Bool) {
        guard presented != isNativePresented else { return }
        presentationGeneration += 1
        let generation = presentationGeneration
        acceptsNativeDismissal = false
        if reducesMotion {
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) { isNativePresented = presented }
            acceptsNativeDismissal = presented
        } else {
            withAnimation(DesignMotion.sidebar, completionCriteria: .logicallyComplete) {
                isNativePresented = presented
            } completion: {
                guard generation == presentationGeneration else { return }
                acceptsNativeDismissal = presented && isPresented
            }
        }
    }

    private func installInitiallyPresentedInspectorIfNeeded() {
        if hasMountedNativeInspector {
            acceptsNativeDismissal = isNativePresented && isPresented
            return
        }
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
