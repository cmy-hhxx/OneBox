import OneBoxDesignSystem
import OneBoxRuntime
import SwiftUI

struct ToolDetailView: View {
    let registration: ToolRegistration?

    @Environment(\.designPalette) private var palette

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignMetrics.space24) {
                if let registration {
                    Text(registration.displayName)
                        .font(DesignTypography.screenTitle)
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)

                    registration.content(context: ToolContext())
                }
            }
            .padding(.horizontal, DesignMetrics.mainInset)
            .padding(.top, DesignMetrics.space48)
            .padding(.bottom, DesignMetrics.space24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .scrollIndicators(.never)
        .background(palette.background)
    }
}
