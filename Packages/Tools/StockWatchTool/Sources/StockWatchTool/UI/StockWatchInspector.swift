import OneBoxDesignSystem
import SwiftUI

@MainActor
struct StockWatchInspector: View {
    let store: MonitorStore
    @Bindable var preferences: StockWatchPreferences
    let selectedInstrumentID: InstrumentID?
    let copyText: (String) -> Bool
    let revealDirectory: (URL) -> Bool

    @Environment(\.designPalette) private var palette

    var body: some View {
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

    private var sectionDivider: some View {
        Rectangle()
            .fill(palette.border)
            .frame(height: 1)
    }
}
