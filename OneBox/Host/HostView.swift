import OneBoxDesignSystem
import OneBoxRuntime
import SwiftUI

public struct HostView: View {
    let catalog: ToolCatalog

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selection: ToolID?
    @State private var isSidebarVisible = true

    public init(catalog: ToolCatalog) {
        self.catalog = catalog
        _selection = State(initialValue: catalog.registrations.first?.id)
    }

    public var body: some View {
        let palette = DesignPalette.resolve(colorScheme)

        HStack(spacing: 0) {
            if isSidebarVisible {
                HostSidebar(
                    catalog: catalog,
                    selection: $selection,
                    onCollapse: toggleSidebar
                )
                .frame(width: DesignMetrics.sidebarWidth)
                .ignoresSafeArea(.container, edges: .top)
                .transition(.move(edge: .leading))
            }

            ToolDetailView(registration: catalog.registration(for: selection))
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
        ) { _ in
            Text("预览内容")
        }
    ])
}
