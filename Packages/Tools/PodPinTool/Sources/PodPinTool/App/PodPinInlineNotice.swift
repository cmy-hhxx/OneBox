import OneBoxDesignSystem
import SwiftUI

struct PodPinNotice: Equatable, Identifiable {
    let id: String
    let title: String
    let message: String
    let copyDetails: String?

    init(error: PresentedError) {
        id = error.errorID
        title = error.summary
        message = error.recoverySuggestion
        copyDetails =
            "PodPin error \(error.errorID) [\(error.code.rawValue)]\n\(error.technicalReason)"
    }

    init(id: String, title: String, message: String) {
        self.id = id
        self.title = title
        self.message = message
        copyDetails = nil
    }
}

struct PodPinInlineNotice: View {
    let notice: PodPinNotice
    let onCopyDetails: (String) -> Void
    let onDismiss: () -> Void

    @Environment(\.designPalette) private var palette

    var body: some View {
        HStack(alignment: .top, spacing: DesignMetrics.space8) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(DesignTypography.body)
                .foregroundStyle(palette.negative)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: DesignMetrics.space4) {
                Text(notice.title)
                    .font(DesignTypography.bodyMedium)
                    .foregroundStyle(palette.textPrimary)

                Text(notice.message)
                    .font(DesignTypography.metadata)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: DesignMetrics.space8)

            if let copyDetails = notice.copyDetails {
                Button("复制错误详情", systemImage: "doc.on.doc") {
                    onCopyDetails(copyDetails)
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .help("复制错误详情")
            }

            Button("关闭提示", systemImage: "xmark", action: onDismiss)
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .help("关闭提示")
        }
        .padding(.horizontal, DesignMetrics.space12)
        .padding(.vertical, DesignMetrics.space8)
        .background(palette.surface)
        .overlay {
            Rectangle()
                .strokeBorder(palette.border, lineWidth: 1)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("podpin.notice")
    }
}
