import OneBoxDesignSystem
import SwiftUI

/// The library list's compact episode row. Selection stays in the list shell;
/// this component owns only row-level playback, queue, and storage affordances.
struct LibraryItemRowView: View {
    let item: LibraryItemRow
    let isSelected: Bool
    let isCurrentItem: Bool
    let isPlaying: Bool
    let downloadSession: DownloadSession
    let playbackTimeline: PlaybackTimelineSession
    let onTogglePlayback: () -> Void
    let onItemAction: (LibraryItemAction) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.oneBoxAccessibilityReduceMotionOverride) private var reduceMotionOverride
    @Environment(\.designPalette) private var palette
    @State private var isHovering = false

    private var showsArtworkControl: Bool {
        isHovering || isSelected || isCurrentItem
    }

    var body: some View {
        HStack(spacing: DesignMetrics.space12) {
            artwork
            metadataInformation
            storageControl
            moreControl
        }
        .padding(.horizontal, DesignMetrics.space12)
        .padding(.vertical, DesignMetrics.space12)
        .frame(minHeight: DesignMetrics.dataRowHeight)
        .background(
            isSelected
                ? palette.selection : (isHovering ? palette.surfaceElevated : palette.surface)
        )
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture(count: 2).onEnded { onItemAction(.playNow) })
        .onHover { isHovering = $0 }
        .animation(
            (reduceMotionOverride ?? reduceMotion) ? nil : DesignMotion.hover, value: isHovering
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAction(named: isPlaying ? "暂停" : "播放") { onTogglePlayback() }
        .help("双击立即播放；空格播放或暂停")
    }

    private var artwork: some View {
        ZStack(alignment: .bottomTrailing) {
            ArtworkThumbnailView(url: item.artworkURL)

            Button(action: onTogglePlayback) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(DesignTypography.metadata.weight(.bold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(
                        width: DesignMetrics.brandMarkSize,
                        height: DesignMetrics.brandMarkSize
                    )
                    .background(palette.surface, in: Circle())
                    .overlay {
                        Circle().strokeBorder(palette.border, lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .padding(DesignMetrics.space4)
            .opacity(showsArtworkControl ? 1 : 0)
            .allowsHitTesting(showsArtworkControl)
            .accessibilityHidden(!showsArtworkControl)
            .accessibilityLabel(isPlaying ? "暂停" : "播放")
            .help(isPlaying ? "暂停" : "播放")
            .animation(
                (reduceMotionOverride ?? reduceMotion) ? nil : DesignMotion.hover,
                value: showsArtworkControl
            )
        }
        .frame(width: 40, height: 40)
        .background(palette.surfaceElevated)
        .clipShape(.rect(cornerRadius: DesignMetrics.space12))
    }

    private var metadataInformation: some View {
        VStack(alignment: .leading, spacing: DesignMetrics.space4) {
            Text(item.title)
                .font(DesignTypography.bodyMedium)
                .foregroundStyle(isCurrentItem ? palette.accent : palette.textPrimary)
                .lineLimit(2)
                .help(item.title)

            Text(subtitle)
                .font(DesignTypography.metadata)
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .help(subtitle)

            if item.storageState == .downloading {
                DownloadProgressView(session: downloadSession, itemID: item.id)
                    .frame(maxWidth: 180)
                    .tint(palette.accent)
            } else if let duration = item.duration, duration > 0 {
                if isCurrentItem {
                    LiveLibraryListeningProgressView(timeline: playbackTimeline)
                        .frame(maxWidth: 150)
                        .tint(palette.accent)
                } else if item.progress > 0 || !item.listeningHistory.intervals.isEmpty {
                    ListeningProgressBar(
                        history: item.listeningHistory,
                        currentTime: item.progress,
                        duration: duration
                    )
                    .frame(maxWidth: 150)
                    .tint(palette.accent)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .layoutPriority(1)
    }

    private var moreControl: some View {
        Menu {
            Button("现在播放") { onItemAction(.playNow) }
            Button("下一项播放") { onItemAction(.enqueueNext) }
            Button("添加到队尾") { onItemAction(.enqueueLast) }
            Divider()
            Button("移动到…") { onItemAction(.move) }
            Divider()
            Button("删除", role: .destructive) { onItemAction(.delete) }
        } label: {
            Image(systemName: "ellipsis")
                .font(DesignTypography.bodyMedium)
                .foregroundStyle(palette.textSecondary)
                .frame(
                    width: DesignMetrics.titlebarControlSize,
                    height: DesignMetrics.titlebarControlSize
                )
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(ToolIconButtonStyle())
        .menuIndicator(.hidden)
        .frame(width: DesignMetrics.titlebarControlSize, alignment: .trailing)
        .help("\(item.title) 的更多操作")
        .accessibilityLabel("\(item.title) 的更多操作")
        .accessibilityIdentifier("library.item-actions.\(item.id.uuidString)")
    }

    @ViewBuilder
    private var storageControl: some View {
        switch item.storageState {
        case .online:
            storageButton(
                "下载到本机",
                systemImage: "arrow.down.circle",
                color: palette.textSecondary
            ) {
                onItemAction(.download)
            }
        case .downloadFailed:
            storageButton(
                "重试下载",
                systemImage: "arrow.clockwise",
                color: palette.negative
            ) {
                onItemAction(.retryDownload)
            }
        case .downloading:
            storageButton(
                "取消下载",
                systemImage: "xmark.circle",
                color: palette.textSecondary
            ) {
                onItemAction(.cancelDownload)
            }
        case .downloaded:
            Image(systemName: "checkmark.circle.fill")
                .font(DesignTypography.body)
                .foregroundStyle(palette.textSecondary)
                .frame(
                    width: DesignMetrics.titlebarControlSize,
                    height: DesignMetrics.titlebarControlSize
                )
                .accessibilityLabel("已下载")
                .help("已下载")
        }
    }

    private func storageButton(
        _ title: String,
        systemImage: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(title, systemImage: systemImage, action: action)
            .buttonStyle(ToolIconButtonStyle())
            .labelStyle(.iconOnly)
            .font(DesignTypography.body)
            .foregroundStyle(color)
            .frame(width: DesignMetrics.titlebarControlSize)
            .help(title)
            .accessibilityLabel(title)
    }

    private var storageColor: Color {
        switch item.storageState {
        case .online, .downloaded:
            palette.textSecondary
        case .downloading:
            palette.accent
        case .downloadFailed:
            palette.negative
        }
    }

    private var subtitle: String {
        var components = [item.author, Optional(item.sourceName)]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if let duration = item.duration {
            components.append(PlaybackTimeFormatter.string(for: duration))
        }

        switch item.storageState {
        case .downloading:
            components.append("下载中")
        case .downloadFailed:
            components.append("下载失败")
        case .online, .downloaded:
            break
        }
        return components.joined(separator: " · ")
    }

    private var accessibilityLabel: String {
        let author = item.author.map { "，\($0)" } ?? ""
        let playback = isCurrentItem ? (isPlaying ? "，正在播放" : "，已暂停") : ""
        return "\(item.title)\(author)，\(item.storageState.label)\(playback)"
    }
}

/// Only the active row observes the half-second clock; the rest of the list
/// stays on its low-frequency library snapshot.
private struct LiveLibraryListeningProgressView: View {
    @ObservedObject var timeline: PlaybackTimelineSession

    var body: some View {
        ListeningProgressBar(
            history: timeline.snapshot.listeningHistory,
            currentTime: timeline.snapshot.currentTime,
            duration: timeline.snapshot.duration
        )
    }
}
