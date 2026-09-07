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
        .padding(.horizontal, DesignMetrics.mainInset)
        .padding(.top, DesignMetrics.space8)
        .padding(.bottom, DesignMetrics.space24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(palette.background)
    }
}
