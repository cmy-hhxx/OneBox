import OneBoxDesignSystem
import OneBoxRuntime
import SwiftUI

struct ToolDetailView: View {
    let registration: ToolRegistration?

    @Environment(\.designPalette) private var palette

    var body: some View {
        Group {
            if let registration {
                registration.content()
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: .infinity,
                        alignment: .topLeading
                    )
            }
        }
        .padding(.horizontal, DesignMetrics.mainInset)
        .padding(.top, DesignMetrics.space8)
        .padding(.bottom, DesignMetrics.space24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(palette.background)
    }
}
