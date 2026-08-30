import OneBoxDesignSystem
import SwiftUI

/// Separates the transport position from listening history: colored spans are
/// media time that actually played, gaps are still unheard, and the marker is
/// the current playhead.
struct ListeningProgressBar: View {
    let history: ListeningHistory
    let currentTime: TimeInterval
    let duration: TimeInterval
    var trackHeight: CGFloat = 5

    @Environment(\.designPalette) private var palette

    var body: some View {
        HStack(spacing: DesignMetrics.space8) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(palette.border)
                    ForEach(Array(history.intervals.enumerated()), id: \.offset) { _, interval in
                        Rectangle()
                            .fill(palette.accent)
                            .frame(width: intervalWidth(interval, totalWidth: proxy.size.width))
                            .offset(x: intervalOffset(interval, totalWidth: proxy.size.width))
                    }
                    Rectangle()
                        .fill(palette.textPrimary)
                        .frame(width: 2)
                        .offset(x: playheadOffset(totalWidth: proxy.size.width))
                }
                .clipShape(Capsule())
            }
            .frame(height: trackHeight)

            if isComplete {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: DesignMetrics.space12, weight: .semibold))
                    .frame(width: DesignMetrics.space16, height: DesignMetrics.space16)
                    .foregroundStyle(palette.accent)
                    .accessibilityHidden(true)
            }
        }
        .frame(height: max(trackHeight, DesignMetrics.space16))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("收听记录")
        .accessibilityValue(accessibilityValue)
    }

    private var validDuration: TimeInterval {
        duration.isFinite && duration > 0 ? duration : 0
    }

    private var isComplete: Bool {
        history.isComplete(duration: validDuration)
    }

    private var accessibilityValue: String {
        guard validDuration > 0 else { return "时长未知" }
        if isComplete { return "已完整听完" }
        let percentage = Int((history.listenedFraction(duration: validDuration) * 100).rounded())
        return "已听 " + String(percentage) + "%，当前位置 "
            + PlaybackTimeFormatter.string(for: currentTime)
    }

    private func intervalWidth(_ interval: ListenedInterval, totalWidth: CGFloat) -> CGFloat {
        guard validDuration > 0 else { return 0 }
        let start = min(max(interval.start, 0), validDuration)
        let end = min(max(interval.end, start), validDuration)
        return max(CGFloat((end - start) / validDuration) * totalWidth, 1)
    }

    private func intervalOffset(_ interval: ListenedInterval, totalWidth: CGFloat) -> CGFloat {
        guard validDuration > 0 else { return 0 }
        return CGFloat(min(max(interval.start / validDuration, 0), 1)) * totalWidth
    }

    private func playheadOffset(totalWidth: CGFloat) -> CGFloat {
        guard validDuration > 0 else { return 0 }
        let fraction = min(max(currentTime / validDuration, 0), 1)
        return min(max(CGFloat(fraction) * totalWidth - 1, 0), max(totalWidth - 2, 0))
    }
}
