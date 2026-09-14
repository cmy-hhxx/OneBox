import OneBoxDesignSystem
import SwiftUI

/// The continuation queue shown in OneBox's shared trailing inspector.
struct NowPlayingQueueView: View {
    @ObservedObject var session: PlaybackQueueSession
    let artworkURL: (AudioItem) -> URL?
    let onPlay: (UUID) -> Void
    let onRemove: (UUID) -> Void
    let onMove: (UUID, Int) -> Void
    let onClear: () -> Void
    let onRetry: () -> Void

    @Environment(\.designPalette) private var palette
    @State private var isClearConfirmationPresented = false

    var body: some View {
        VStack(alignment: .leading, spacing: DesignMetrics.space12) {
            if !session.entries.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: DesignMetrics.space12) {
                    Text("\(session.entries.count) 项待播")
                        .font(DesignTypography.metadata.monospacedDigit())
                        .foregroundStyle(palette.textSecondary)

                    Spacer(minLength: DesignMetrics.space8)

                    Button(role: .destructive) {
                        isClearConfirmationPresented = true
                    } label: {
                        Text("清空队列")
                            .foregroundStyle(palette.negative)
                    }
                    .buttonStyle(ToolActionButtonStyle(kind: .quiet, compact: true))
                    .help("移除全部待播项目，保留当前播放")
                }
            }

            if let message = session.errorMessage {
                queueError(message: message)
            }

            if session.entries.isEmpty {
                emptyState
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(Array(session.entries.enumerated()), id: \.element.id) {
                        index, entry in
                        NowPlayingQueueRow(
                            entry: entry,
                            index: index,
                            count: session.entries.count,
                            artworkURL: artworkURL(entry.item),
                            onPlay: onPlay,
                            onRemove: onRemove,
                            onMove: onMove
                        )

                        if index < session.entries.count - 1 {
                            Rectangle()
                                .fill(palette.border)
                                .frame(height: 1)
                                .accessibilityHidden(true)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .tint(palette.accent)
        .contextMenu {
            if !session.entries.isEmpty {
                Button("清空队列", role: .destructive) {
                    isClearConfirmationPresented = true
                }
            }
        }
        .confirmationDialog(
            "清空待播队列？",
            isPresented: $isClearConfirmationPresented
        ) {
            Button("清空队列", role: .destructive, action: onClear)
            Button("取消", role: .cancel) {}
        } message: {
            Text("将移除全部待播项目，当前播放内容不会停止。")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("now-playing.queue")
    }

    private func queueError(message: String) -> some View {
        HStack(alignment: .top, spacing: DesignMetrics.space8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(palette.negative)
                .accessibilityHidden(true)

            Text(message)
                .font(DesignTypography.body)
                .foregroundStyle(palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: DesignMetrics.space8)

            Button("重试", action: onRetry)
                .font(DesignTypography.bodyMedium)
                .buttonStyle(ToolActionButtonStyle(kind: .secondary, compact: true))
        }
        .padding(DesignMetrics.space12)
        .background(palette.negativeSurface, in: .rect(cornerRadius: DesignMetrics.cornerRadius))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("队列载入失败。\(message)")
        .accessibilityAction(named: "重试", onRetry)
    }

    private var emptyState: some View {
        VStack(spacing: DesignMetrics.space8) {
            Image(systemName: "text.line.first.and.arrowtriangle.forward")
                .font(.system(size: 24, weight: .regular))
                .foregroundStyle(palette.accent)
                .padding(DesignMetrics.space16)
                .accessibilityHidden(true)

            Text("队列为空")
                .font(DesignTypography.sectionTitle)
                .foregroundStyle(palette.textPrimary)

            Text("从资料库将音频加入下一项播放或队尾。")
                .font(DesignTypography.body)
                .foregroundStyle(palette.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
        }
        .padding(.vertical, DesignMetrics.space24)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

private struct NowPlayingQueueRow: View {
    let entry: PlaybackQueueEntry
    let index: Int
    let count: Int
    let artworkURL: URL?
    let onPlay: (UUID) -> Void
    let onRemove: (UUID) -> Void
    let onMove: (UUID, Int) -> Void

    @Environment(\.designPalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.oneBoxAccessibilityReduceMotionOverride) private var reduceMotionOverride
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: DesignMetrics.space8) {
            Button {
                onPlay(entry.id)
            } label: {
                HStack(spacing: DesignMetrics.space12) {
                    ArtworkThumbnailView(url: artworkURL, maxPixelSize: 180)
                        .frame(width: 40, height: 40)
                        .background(palette.surfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: DesignMetrics.space12))
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: DesignMetrics.space4) {
                        Text(entry.item.title)
                            .font(DesignTypography.bodyMedium)
                            .foregroundStyle(palette.textPrimary)
                            .lineLimit(2)

                        Text(subtitle)
                            .font(DesignTypography.metadata)
                            .foregroundStyle(palette.textSecondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("播放 \(entry.item.title)")
            .help("播放 \(entry.item.title)")

            Menu {
                Button("立即播放", systemImage: "play.fill") {
                    onPlay(entry.id)
                }

                Divider()

                Button("上移", systemImage: "arrow.up") {
                    onMove(entry.id, index - 1)
                }
                .disabled(index == 0)

                Button("下移", systemImage: "arrow.down") {
                    onMove(entry.id, index + 1)
                }
                .disabled(index >= count - 1)

                Divider()

                Button("从队列移除", systemImage: "minus.circle", role: .destructive) {
                    onRemove(entry.id)
                }
            } label: {
                Label("队列项目操作", systemImage: "ellipsis")
                    .labelStyle(.iconOnly)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(palette.textSecondary)
                    .frame(width: 32, height: 32)
            }
            .menuStyle(.button)
            .buttonStyle(ToolIconButtonStyle())
            .menuIndicator(.hidden)
            .accessibilityLabel("\(entry.item.title) 的队列操作")
            .help("队列项目操作")
        }
        .padding(.vertical, DesignMetrics.space12)
        .frame(minHeight: 64)
        .background(isHovered ? palette.surfaceElevated : palette.surface)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .animation(
            (reduceMotionOverride ?? reduceMotion) ? nil : DesignMotion.hover, value: isHovered
        )
        .contextMenu {
            Button("立即播放", action: { onPlay(entry.id) })
            Button("从队列移除", role: .destructive, action: { onRemove(entry.id) })
        }
    }

    private var authorOrSource: String {
        if let author = entry.item.author?.trimmingCharacters(in: .whitespacesAndNewlines),
            !author.isEmpty
        {
            return author
        }
        switch entry.item.platform {
        case .bilibili: return "哔哩哔哩"
        case .douyin: return "抖音"
        case .fireside: return "Fireside"
        case .xiaoyuzhou: return "小宇宙"
        case .fixture: return "PodPin 资料库"
        }
    }

    private var subtitle: String {
        [
            authorOrSource,
            entry.item.duration.map(PlaybackTimeFormatter.string(for:)),
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }
}

struct NowPlayingBottomSwitcher: View {
    @Binding var queueIsPresented: Bool
    let keyboardFocus: FocusState<Bool>.Binding
    let accessibilityFocus: AccessibilityFocusState<Bool>.Binding

    @Environment(\.designPalette) private var palette

    var body: some View {
        Button {
            queueIsPresented.toggle()
        } label: {
            Label(
                queueIsPresented ? "隐藏继续播放" : "显示继续播放",
                systemImage: queueIsPresented ? "rectangle.righthalf.inset.filled" : "list.bullet"
            )
            .labelStyle(.iconOnly)
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(queueIsPresented ? palette.accent : palette.textSecondary)
            .frame(width: 32, height: 32)
        }
        .buttonStyle(ToolIconButtonStyle(isSelected: queueIsPresented))
        .focused(keyboardFocus)
        .accessibilityFocused(accessibilityFocus)
        .accessibilityLabel(queueIsPresented ? "隐藏继续播放" : "显示继续播放")
        .accessibilityIdentifier("now-playing.queue-toggle")
        .help(queueIsPresented ? "隐藏继续播放" : "显示继续播放")
    }
}
