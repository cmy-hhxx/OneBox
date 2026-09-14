import OneBoxDesignSystem
import OneBoxRuntime
import SwiftUI

struct HostSidebar: View {
    let catalog: ToolCatalog
    let selection: ToolID?
    let onSelect: (ToolID) -> Void
    let onCollapse: () -> Void
    let debugLogStore: DebugLogStore?
    let onOpenDiagnostics: () -> Void
    var isDiagnosticsPresented = false
    var isCollapsed = false
    var expandedWidth = DesignMetrics.sidebarWidth

    @Environment(\.designPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            VStack(spacing: 4) {
                ForEach(catalog.registrations) { registration in
                    HostSidebarRow(
                        registration: registration, isSelected: selection == registration.id,
                        isCollapsed: isCollapsed
                    ) {
                        onSelect(registration.id)
                    }
                }
            }
            .padding(.top, 8)

            Spacer(minLength: 24)

            if let debugLogStore {
                Button(action: onOpenDiagnostics) {
                    HStack(spacing: 0) {
                        SidebarSymbol(name: "ladybug")
                            .frame(width: 12, height: 20)

                        SidebarLabelSlot(isCollapsed: isCollapsed) {
                            HStack(spacing: 8) {
                                Text("调试日志")
                                Spacer(minLength: 0)
                                if debugLogStore.isEnabled {
                                    Circle().fill(palette.positive).frame(width: 6, height: 6)
                                    Text("记录中")
                                        .font(DesignTypography.metadata)
                                        .foregroundStyle(
                                            isDiagnosticsPresented
                                                ? palette.textOnAccent : palette.textSecondary)
                                }
                            }
                            .padding(.leading, 12)
                            .frame(width: expandedWidth - 60)
                        }
                    }
                    .frame(height: DesignMetrics.sidebarRowHeight)
                }
                .buttonStyle(
                    ToolActionButtonStyle(kind: isDiagnosticsPresented ? .primary : .secondary)
                )
                .help(isDiagnosticsPresented ? "收起调试日志（⇧⌘L）" : "查看三个工具的原始错误（⇧⌘L）")
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("调试日志")
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { onOpenDiagnostics() }
                .accessibilityValue(
                    "\(isDiagnosticsPresented ? "已展开" : "已收起") · \(debugLogStore.isEnabled ? "正在记录" : "未开启")"
                )
                .accessibilityIdentifier("onebox.openDiagnostics")
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(palette.sidebar, in: .rect(cornerRadius: 24))
        .overlay { RoundedRectangle(cornerRadius: 24).strokeBorder(palette.surface, lineWidth: 1) }
        .shadow(color: palette.sidebarOutline, radius: 1, x: 0, y: 0)
        .shadow(color: palette.sidebarShadow, radius: 12, x: 0, y: 1)
    }

    private var header: some View {
        GeometryReader { _ in
            ZStack(alignment: .topLeading) {
                HStack(spacing: 0) {
                    OneBoxBrandMark()
                    SidebarLabelSlot(isCollapsed: isCollapsed) {
                        Text("OneBox")
                            .font(DesignTypography.sidebarTitle)
                            .foregroundStyle(palette.textPrimary)
                            .padding(.leading, 8)
                    }
                }
                .frame(width: isCollapsed ? 24 : max(24, expandedWidth - 78), height: 24)
                .offset(x: 6, y: isCollapsed ? 44 : 10)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("OneBox")
                .accessibilityAddTraits(.isHeader)

                SidebarToggleButton(
                    accessibilityTitle: isCollapsed ? "展开侧栏" : "收起侧栏", action: onCollapse
                )
                .offset(x: isCollapsed ? 2 : expandedWidth - 64, y: isCollapsed ? 0 : 6)
                .accessibilityValue(isCollapsed ? "已收起" : "已展开")
            }
        }
        // Both states reserve the compact header's height so navigation never jumps vertically.
        .frame(height: 68)
    }
}
