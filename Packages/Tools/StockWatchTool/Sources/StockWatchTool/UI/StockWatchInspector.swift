import OneBoxDesignSystem
import SwiftUI

@MainActor
struct StockWatchInspector: View {
    @ObservedObject var store: MonitorStore
    @Bindable var preferences: StockWatchPreferences
    let selectedInstrumentID: InstrumentID?
    let copyText: (String) -> Bool
    let revealDirectory: (URL) -> Bool
    let close: () -> Void

    @Environment(\.designPalette) private var palette

    var body: some View {
        ToolInspectorPanel("检查器", closeLabel: "关闭检查器", close: close) {
            VStack(alignment: .leading, spacing: DesignMetrics.space16) {
                SelectedInstrumentInspectorSection(
                    store: store,
                    selectedInstrumentID: selectedInstrumentID
                )
                sectionDivider
                StockWatchAlertInspectorSection(
                    store: store,
                    preferences: preferences
                )
                sectionDivider
                StockWatchDataInspectorSection(
                    store: store,
                    preferences: preferences,
                    copyText: copyText,
                    revealDirectory: revealDirectory
                )
            }
        }
    }

    private var sectionDivider: some View {
        Rectangle()
            .fill(palette.border)
            .frame(height: 1)
    }
}
