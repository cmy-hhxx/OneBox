import OneBoxDesignSystem
import SwiftUI

struct WorkspacePage<Content: View>: View {
    let content: Content

    @Environment(\.designPalette) private var palette

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ScrollView {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, DesignMetrics.space8)
        }
        .scrollIndicators(.automatic)
        .background(palette.surface)
    }
}

enum PlaybackTimeFormatter {
    static func string(for time: TimeInterval?) -> String {
        guard let time, time.isFinite, time >= 0 else { return "—" }
        let seconds = max(0, Int(time.rounded(.down)))
        let hours = seconds / 3_600
        if hours > 0 {
            return String(
                format: "%d:%02d:%02d",
                hours,
                (seconds % 3_600) / 60,
                seconds % 60
            )
        }
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    static func remainingString(current: TimeInterval?, duration: TimeInterval?) -> String {
        guard let current, current.isFinite,
            let duration, duration.isFinite, duration > 0
        else { return "—" }

        return "−\(string(for: max(duration - max(current, 0), 0)))"
    }
}
