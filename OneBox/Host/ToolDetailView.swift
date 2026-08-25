import OneBoxDesignSystem
import OneBoxRuntime
import SwiftUI

struct ToolDetailView: View {
    let registration: ToolRegistration?

    @Environment(\.designPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: DesignMetrics.space24) {
            if let registration {
                Text(registration.displayName)
                    .font(DesignTypography.screenTitle)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)

                registration.content()
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: .infinity,
                        alignment: .topLeading
                    )
            }
        }
        .padding(.horizontal, DesignMetrics.mainInset)
        .padding(.top, DesignMetrics.space48)
        .padding(.bottom, DesignMetrics.space24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(palette.background)
    }
}
