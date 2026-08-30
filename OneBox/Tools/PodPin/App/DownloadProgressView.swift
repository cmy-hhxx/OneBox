import OneBoxDesignSystem
import SwiftUI

/// Observes only the high-frequency download session so parent workspaces do
/// not redraw for every network progress callback.
struct DownloadProgressView: View {
    @ObservedObject var session: DownloadSession
    let itemID: UUID?

    @Environment(\.designPalette) private var palette

    var body: some View {
        if isActive {
            HStack(spacing: DesignMetrics.space8) {
                if let fraction {
                    ProgressView(value: fraction)
                        .progressViewStyle(.linear)
                        .accessibilityLabel("下载进度")
                        .accessibilityValue(
                            Text(fraction, format: .percent.precision(.fractionLength(0)))
                        )
                    Text(fraction, format: .percent.precision(.fractionLength(0)))
                        .font(DesignTypography.metadata.monospacedDigit())
                        .foregroundStyle(palette.textSecondary)
                        .accessibilityHidden(true)
                } else {
                    ProgressView()
                        .progressViewStyle(.linear)
                        .accessibilityLabel("下载进度")
                        .accessibilityValue("正在下载")
                }
                if let bytesPerSecond = session.bytesPerSecond {
                    Text(Self.speedFormatter.string(fromByteCount: Int64(bytesPerSecond)) + "/秒")
                        .font(DesignTypography.metadata.monospacedDigit())
                        .foregroundStyle(palette.textSecondary)
                        .accessibilityLabel("下载速度")
                }
            }
            .tint(palette.accent)
            .accessibilityIdentifier("download.progress")
        }
    }

    private var isActive: Bool {
        guard let activeItemID = session.activeItemID else { return false }
        return itemID == nil || itemID == activeItemID
    }

    private var fraction: Double? {
        guard let progress = session.progress, progress.isFinite else { return nil }
        return min(max(progress, 0), 1)
    }

    private static let speedFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter
    }()
}
