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
        VStack(alignment: .leading, spacing: DesignMetrics.space12) {
            header

            ScrollView {
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
        .accessibilityAction(.escape, close)
    }

    private var header: some View {
        HStack {
            Text("检查器")
                .font(DesignTypography.sectionTitle)

            Spacer(minLength: 0)

            Button("关闭检查器", systemImage: "xmark", action: close)
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .frame(width: DesignMetrics.space24, height: DesignMetrics.space24)
                .accessibilityLabel("关闭检查器")
        }
    }

    private var sectionDivider: some View {
        Rectangle()
            .fill(palette.border)
            .frame(height: 1)
    }
}
