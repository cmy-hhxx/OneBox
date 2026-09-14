import OneBoxDesignSystem
import OneBoxRuntime
import SwiftUI

struct ToolDetailView: View {
    let registration: ToolRegistration?
    let onContentPresented: @MainActor @Sendable (ToolID) -> Void
    let onContentReady: (ToolID) -> Void

    @Environment(\.designPalette) private var palette

    var body: some View {
        Group {
            if let registration {
                VStack(alignment: .leading, spacing: DesignMetrics.space16) {
                    VStack(alignment: .leading, spacing: DesignMetrics.space4) {
                        Text(registration.displayName)
                            .font(DesignTypography.pageTitle)
                            .foregroundStyle(palette.textPrimary)
                            .accessibilityAddTraits(.isHeader)
                        if !registration.summary.isEmpty {
                            Text(registration.summary)
                                .font(DesignTypography.metadata)
                                .foregroundStyle(palette.textSecondary)
                        }
                    }
                    .padding(.top, DesignMetrics.space8)
                    registration.content()
                        .environment(
                            \.toolContentReadinessReporter,
                            ToolContentReadinessReporter {
                                onContentReady(registration.id)
                            }
                        )
                        .frame(
                            maxWidth: .infinity,
                            maxHeight: .infinity,
                            alignment: .topLeading
                        )
                        .onAppear {
                            onContentPresented(registration.id)
                        }
                }
            }
        }
        .padding(.horizontal, DesignMetrics.mainInset)
        .padding(.top, DesignMetrics.space8)
        .padding(.bottom, DesignMetrics.space24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(palette.background)
    }
}
