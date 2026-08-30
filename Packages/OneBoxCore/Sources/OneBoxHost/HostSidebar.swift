import OneBoxDesignSystem
import OneBoxRuntime
import SwiftUI

struct HostSidebar: View {
    let catalog: ToolCatalog
    @Binding var selection: ToolID?
    let onCollapse: () -> Void

    @Environment(\.designPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Spacer(minLength: 0)

                SidebarToggleButton(
                    accessibilityTitle: "收起侧栏",
                    action: onCollapse
                )
            }
            .frame(height: DesignMetrics.titlebarControlSize)

            OneBoxBrandTitle()
                .padding(.horizontal, DesignMetrics.sidebarTextInset)
                .frame(
                    maxWidth: .infinity,
                    minHeight: DesignMetrics.sidebarRowHeight,
                    alignment: .leading
                )
                .padding(.top, DesignMetrics.space16)

            VStack(spacing: DesignMetrics.space4) {
                ForEach(catalog.registrations) { registration in
                    HostSidebarRow(
                        registration: registration,
                        isSelected: selection == registration.id
                    ) {
                        selection = registration.id
                    }
                }
            }
            .padding(.top, DesignMetrics.space16)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, DesignMetrics.sidebarEdgeInset)
        .padding(.bottom, DesignMetrics.space16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(palette.sidebar)
    }
}
