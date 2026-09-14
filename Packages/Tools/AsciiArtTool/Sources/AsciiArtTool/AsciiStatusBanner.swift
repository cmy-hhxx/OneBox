import OneBoxDesignSystem
import OneBoxRuntime
import SwiftUI

@MainActor
struct AsciiStatusBanner: View {
    let message: String
    let retry: (() -> Void)?

    @Environment(\.designPalette) private var palette
    @Environment(\.openToolDiagnostics) private var openToolDiagnostics

    var body: some View {
        HStack(alignment: .top, spacing: DesignMetrics.space12) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(DesignTypography.metric)
                .foregroundStyle(palette.negative)
                .frame(width: 40, height: 40)
                .background(palette.negativeSurface, in: .circle)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: DesignMetrics.space8) {
                Text("操作未完成")
                    .font(DesignTypography.bodyMedium)
                    .foregroundStyle(palette.textPrimary)
                Text(message)
                    .font(DesignTypography.body)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: DesignMetrics.space8) {
                    if let retry {
                        Button("重试", systemImage: "arrow.clockwise", action: retry)
                            .buttonStyle(ToolActionButtonStyle(kind: .secondary, compact: true))
                    }
                    Button("查看日志", systemImage: "text.alignleft") {
                        openToolDiagnostics()
                    }
                    .buttonStyle(ToolActionButtonStyle(kind: .quiet, compact: true))
                }
            }
        }
        .padding(DesignMetrics.space16)
        .background(palette.surface, in: .rect(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16).strokeBorder(palette.border, lineWidth: 1)
        }
        .shadow(color: palette.dropdownContactShadow, radius: 1, y: 1)
        .shadow(color: palette.dropdownAmbientShadow, radius: 4, y: 4)
        .accessibilityAddTraits(.updatesFrequently)
    }
}
