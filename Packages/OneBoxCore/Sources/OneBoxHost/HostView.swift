import OneBoxDesignSystem
import OneBoxRuntime
import SwiftUI

public struct HostView: View {
    let catalog: ToolCatalog
    let onInitialContentReady: @MainActor @Sendable () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selection: ToolID?
    @State private var isSidebarVisible = true
    @State private var hasInitialContentReady = false
    @State private var performanceTrace: HostPerformanceTrace

    public init(
        catalog: ToolCatalog,
        onInitialContentReady: @escaping @MainActor @Sendable () -> Void = {}
    ) {
        self.catalog = catalog
        self.onInitialContentReady = onInitialContentReady
        let initialSelection = catalog.registrations.first?.id
        _selection = State(initialValue: initialSelection)
        _performanceTrace = State(
            initialValue: HostPerformanceTrace(initialToolID: initialSelection)
        )
    }

    public var body: some View {
        let palette = DesignPalette.resolve(colorScheme)

        HStack(spacing: 0) {
            if isSidebarVisible {
                HostSidebar(
                    catalog: catalog,
                    selection: selection,
                    onSelect: activateTool,
                    onCollapse: toggleSidebar
                )
                .frame(width: DesignMetrics.sidebarWidth)
                .ignoresSafeArea(.container, edges: .top)
                .transition(.move(edge: .leading))
            }

            ToolDetailView(
                registration: catalog.registration(for: selection),
                onContentPresented: performanceTrace.contentDidAppear,
                onContentReady: contentDidBecomeReady
            )
        }
        .overlay(alignment: .topLeading) {
            if !isSidebarVisible {
                SidebarToggleButton(
                    accessibilityTitle: "展开侧栏",
                    action: toggleSidebar
                )
                .padding(.leading, DesignMetrics.collapsedToggleLeadingInset)
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: .topLeading
                )
                .ignoresSafeArea(.container, edges: .top)
                .transition(.opacity)
            }
        }
        .environment(\.designPalette, palette)
        .tint(palette.accent)
        .background(palette.background)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(
            hasInitialContentReady ? "onebox.main.ready" : "onebox.main.loading"
        )
    }

    private func activateTool(_ toolID: ToolID) {
        guard selection != toolID else { return }
        performanceTrace.beginActivation(for: toolID)
        selection = toolID
    }

    private func toggleSidebar() {
        if reduceMotion {
            isSidebarVisible.toggle()
        } else {
            withAnimation(.smooth(duration: 0.2)) {
                isSidebarVisible.toggle()
            }
        }
    }

    private func contentDidBecomeReady(for toolID: ToolID) {
        guard performanceTrace.contentDidBecomeReady(for: toolID) else { return }
        guard !hasInitialContentReady else { return }
        hasInitialContentReady = true
        onInitialContentReady()
    }
}

#Preview("Light") {
    HostView(catalog: .preview)
        .frame(width: 1048, height: 648)
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    HostView(catalog: .preview)
        .frame(width: 1048, height: 648)
        .preferredColorScheme(.dark)
}

extension ToolCatalog {
    fileprivate static let preview = ToolCatalog(registrations: [
        ToolRegistration(
            id: ToolID(rawValue: "preview"),
            displayName: "预览工具"
        ) {
            Text("预览内容")
        }
    ])
}
