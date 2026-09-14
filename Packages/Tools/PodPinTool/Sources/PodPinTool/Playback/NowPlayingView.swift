import AVFoundation
import AVKit
import AppKit
import OneBoxDesignSystem
import SwiftUI

/// Layout values for the focused player inside the OneBox content area.
struct NowPlayingLayoutMetrics: Equatable {
    let isHorizontal: Bool
    let usesCompactTypography: Bool
    let artworkSize: CGFloat
    let contentWidth: CGFloat
    let artworkMetadataSpacing: CGFloat
    let metadataProgressSpacing: CGFloat
    let progressTransportSpacing: CGFloat

    init(availableSize: CGSize) {
        isHorizontal = availableSize.width >= 600
        usesCompactTypography = !isHorizontal && availableSize.height < 400
        if isHorizontal {
            artworkSize = min(256, max(120, availableSize.height * 0.75))
            contentWidth = min(380, availableSize.width - artworkSize - 32)
        } else {
            contentWidth = min(420, max(0, availableSize.width))
            let detailsHeight: CGFloat = usesCompactTypography ? 200 : 260
            artworkSize = min(contentWidth, min(240, max(80, availableSize.height - detailsHeight)))
        }

        let isCompactHeight = availableSize.height < 480
        artworkMetadataSpacing = isCompactHeight ? 12 : 16
        metadataProgressSpacing = isCompactHeight ? 8 : 12
        progressTransportSpacing = isCompactHeight ? 4 : 8
    }
}

/// Focused playback with native macOS controls and OneBox design tokens.
struct NowPlayingView: View {
    @Binding var queueIsPresented: Bool
    @ObservedObject var playbackIdentity: PlaybackIdentitySession
    let playbackTimeline: PlaybackTimelineSession
    let output: PlaybackOutputSession
    @ObservedObject var queue: PlaybackQueueSession
    let downloadSession: DownloadSession
    let outputController: AudioPlaybackController
    let backLabel: String
    let onClose: () -> Void
    let onTogglePlayback: () -> Void
    let onSkipBackward: () -> Void
    let onSkipForward: () -> Void
    let onSeek: (TimeInterval) -> Void
    let onSetRate: (Double) -> Void
    let onSetVolume: (Double) -> Void
    let onCommitVolume: () -> Void
    let onStartDownload: (AudioItem) -> Void
    let onCancelDownload: (UUID) -> Void
    let onPlayQueueItem: (UUID) -> Void
    let onRemoveQueueItem: (UUID) -> Void
    let onMoveQueueItem: (UUID, Int) -> Void
    let onClearQueue: () -> Void
    let onRetryQueue: () -> Void
    let artworkURL: (AudioItem) -> URL?

    @FocusState private var isQueueButtonKeyboardFocused: Bool
    @AccessibilityFocusState private var isQueueButtonAccessibilityFocused: Bool
    @Environment(\.designPalette) private var palette

    var body: some View {
        GeometryReader { proxy in
            NowPlayingHero(
                playbackIdentity: playbackIdentity,
                playbackTimeline: playbackTimeline,
                output: output,
                downloadSession: downloadSession,
                outputController: outputController,
                availableSize: proxy.size,
                queueIsPresented: $queueIsPresented,
                queueButtonKeyboardFocus: $isQueueButtonKeyboardFocused,
                queueButtonAccessibilityFocus: $isQueueButtonAccessibilityFocused,
                backLabel: backLabel,
                onClose: onClose,
                onTogglePlayback: onTogglePlayback,
                onSkipBackward: onSkipBackward,
                onSkipForward: onSkipForward,
                onSeek: onSeek,
                onSetRate: onSetRate,
                onSetVolume: onSetVolume,
                onCommitVolume: onCommitVolume,
                onStartDownload: onStartDownload,
                onCancelDownload: onCancelDownload
            )
        }
        .toolInspector(
            isPresented: $queueIsPresented,
            title: "继续播放",
            closeLabel: "关闭继续播放",
            widthPolicy: .queue,
            onDismiss: restoreQueueButtonFocus
        ) {
            NowPlayingQueueView(
                session: queue,
                artworkURL: artworkURL,
                onPlay: onPlayQueueItem,
                onRemove: onRemoveQueueItem,
                onMove: onMoveQueueItem,
                onClear: onClearQueue,
                onRetry: onRetryQueue
            )
        }
        .background(palette.surface)
        .tint(palette.accent)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("now-playing.player")
    }

    private func restoreQueueButtonFocus() {
        Task { @MainActor in
            await Task.yield()
            guard !queueIsPresented else { return }
            isQueueButtonKeyboardFocused = true
            isQueueButtonAccessibilityFocused = true
        }
    }
}

private struct NowPlayingHero: View {
    @ObservedObject var playbackIdentity: PlaybackIdentitySession
    let playbackTimeline: PlaybackTimelineSession
    let output: PlaybackOutputSession
    let downloadSession: DownloadSession
    let outputController: AudioPlaybackController
    let availableSize: CGSize
    @Binding var queueIsPresented: Bool
    let queueButtonKeyboardFocus: FocusState<Bool>.Binding
    let queueButtonAccessibilityFocus: AccessibilityFocusState<Bool>.Binding
    let backLabel: String
    let onClose: () -> Void
    let onTogglePlayback: () -> Void
    let onSkipBackward: () -> Void
    let onSkipForward: () -> Void
    let onSeek: (TimeInterval) -> Void
    let onSetRate: (Double) -> Void
    let onSetVolume: (Double) -> Void
    let onCommitVolume: () -> Void
    let onStartDownload: (AudioItem) -> Void
    let onCancelDownload: (UUID) -> Void
    @Environment(\.designPalette) private var palette

    var body: some View {
        let snapshot = playbackIdentity.snapshot
        let contentSize = CGSize(
            width: max(availableSize.width - (DesignMetrics.space16 * 2), 0),
            height: max(
                availableSize.height
                    - (DesignMetrics.space16 * 2)
                    - 32
                    - DesignMetrics.space12,
                0
            )
        )
        let metrics = NowPlayingLayoutMetrics(availableSize: contentSize)

        VStack(spacing: DesignMetrics.space12) {
            header

            playerStage(snapshot: snapshot, metrics: metrics)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(DesignMetrics.space16)
        .foregroundStyle(palette.textPrimary)
    }

    private var header: some View {
        HStack(spacing: DesignMetrics.space12) {
            Button(action: onClose) {
                Label(backLabel, systemImage: "chevron.left")
                    .font(DesignTypography.bodyMedium)
                    .foregroundStyle(palette.textSecondary)
            }
            .buttonStyle(ToolActionButtonStyle(kind: .quiet, compact: true))
            .accessibilityLabel(backLabel)
            .accessibilityIdentifier("now-playing.back")
            .help(backLabel)

            Spacer(minLength: DesignMetrics.space8)

            NowPlayingOutputControl(
                output: output,
                outputController: outputController,
                onSetVolume: onSetVolume,
                onCommitVolume: onCommitVolume
            )

            NowPlayingBottomSwitcher(
                queueIsPresented: $queueIsPresented,
                keyboardFocus: queueButtonKeyboardFocus,
                accessibilityFocus: queueButtonAccessibilityFocus
            )
        }
        .frame(height: 32)
    }

    private func playerStage(
        snapshot: PlaybackIdentitySnapshot,
        metrics: NowPlayingLayoutMetrics
    ) -> some View {
        Group {
            if metrics.isHorizontal {
                HStack(spacing: DesignMetrics.space32) {
                    artwork(url: snapshot.artworkURL, size: metrics.artworkSize)
                    playbackDetails(snapshot: snapshot, metrics: metrics)
                }
            } else {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)

                    artwork(url: snapshot.artworkURL, size: metrics.artworkSize)

                    Spacer().frame(height: metrics.artworkMetadataSpacing)

                    playbackDetails(snapshot: snapshot, metrics: metrics)

                    Spacer(minLength: 0)
                }
                .frame(width: metrics.contentWidth)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func playbackDetails(
        snapshot: PlaybackIdentitySnapshot,
        metrics: NowPlayingLayoutMetrics
    ) -> some View {
        VStack(spacing: 0) {
            metadata(snapshot, compact: metrics.usesCompactTypography)
            Spacer().frame(height: metrics.metadataProgressSpacing)
            progress(snapshot)
            Spacer().frame(height: metrics.progressTransportSpacing)
            transport(snapshot)
        }
        .frame(width: metrics.contentWidth)
    }

    private func artwork(url: URL?, size: CGFloat) -> some View {
        ArtworkThumbnailView(
            url: url, maxPixelSize: 900, placeholderFont: DesignTypography.artworkSymbol
        )
        .frame(width: size, height: size)
        .background(palette.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: DesignMetrics.cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: DesignMetrics.cornerRadius)
                .strokeBorder(palette.border, lineWidth: 1)
        }
        .id(url?.absoluteString ?? "no-artwork")
        .accessibilityHidden(true)
    }

    private func metadata(_ snapshot: PlaybackIdentitySnapshot, compact: Bool) -> some View {
        let item = snapshot.item
        let title = item?.title ?? "暂无播放内容"

        return VStack(alignment: .leading, spacing: DesignMetrics.space4) {
            HStack(alignment: .firstTextBaseline, spacing: DesignMetrics.space8) {
                Text(title)
                    .font(compact ? DesignTypography.sectionTitle : DesignTypography.metric)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(compact ? 2 : 3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .help(title)

                if let item {
                    NowPlayingItemMenu(
                        item: item,
                        onStartDownload: onStartDownload,
                        onCancelDownload: onCancelDownload
                    )
                }
            }

            Text(sourceDescription(for: item))
                .font(DesignTypography.body)
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: DesignMetrics.space8) {
                Label(
                    stateLabel(for: snapshot.phase), systemImage: stateSymbol(for: snapshot.phase)
                )
                .lineLimit(1)
                .foregroundStyle(stateColor(for: snapshot.phase))
            }
            .font(DesignTypography.metadata)

            if let item, item.downloadState == .downloading {
                NowPlayingDownloadProgress(session: downloadSession, itemID: item.id)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(item == nil ? "now-playing.empty-title" : "now-playing.title")
    }

    private func sourceDescription(for item: AudioItem?) -> String {
        guard let item else { return "返回资料库选择一条音频" }
        let author = item.author?.trimmingCharacters(in: .whitespacesAndNewlines)
        let platform: String
        switch item.platform {
        case .bilibili: platform = "哔哩哔哩"
        case .douyin: platform = "抖音"
        case .fireside: platform = "Fireside"
        case .xiaoyuzhou: platform = "小宇宙"
        case .fixture: platform = "PodPin 资料库"
        }
        guard let author, !author.isEmpty else { return platform }
        return "\(author) · \(platform)"
    }

    private func stateLabel(for phase: PlaybackPhase) -> String {
        switch phase {
        case .playing: "正在播放"
        case .buffering: "正在缓冲"
        case .loading: "正在准备"
        case .paused: "已暂停"
        case .finished: "播放完成"
        case .replayPending: "准备重播"
        case .failed: "播放遇到问题"
        case .idle: "等待播放"
        }
    }

    private func stateSymbol(for phase: PlaybackPhase) -> String {
        switch phase {
        case .playing: "waveform"
        case .buffering: "ellipsis"
        case .loading: "clock"
        case .paused: "pause.fill"
        case .finished: "checkmark"
        case .replayPending: "arrow.counterclockwise"
        case .failed: "exclamationmark.triangle.fill"
        case .idle: "pause.circle"
        }
    }

    private func stateColor(for phase: PlaybackPhase) -> Color {
        switch phase {
        case .playing, .finished: palette.positive
        case .buffering, .loading, .replayPending: palette.info
        case .failed: palette.negative
        case .idle, .paused: palette.textSecondary
        }
    }

    private func progress(_ snapshot: PlaybackIdentitySnapshot) -> some View {
        NowPlayingProgressControl(
            timeline: playbackTimeline,
            isPlayable: canControlPlayback(snapshot),
            onSeek: onSeek
        )
    }

    private func transport(_ snapshot: PlaybackIdentitySnapshot) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: DesignMetrics.space8) {
                playbackRate(snapshot)
                Spacer(minLength: 0)
                transportButtons(snapshot)
                Spacer(minLength: 0)
                playbackRate(snapshot)
                    .hidden()
                    .accessibilityHidden(true)
            }

            HStack(spacing: DesignMetrics.space8) {
                playbackRate(snapshot)
                Spacer(minLength: 0)
                transportButtons(snapshot)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func playbackRate(_ snapshot: PlaybackIdentitySnapshot) -> some View {
        NowPlayingRateMenu(rate: snapshot.rate, onSetRate: onSetRate)
            .fixedSize()
    }

    private func transportButtons(_ snapshot: PlaybackIdentitySnapshot) -> some View {
        HStack(spacing: DesignMetrics.space8) {
            NowPlayingTransportButton(
                symbol: "gobackward.15",
                label: "后退 15 秒",
                enabled: canControlPlayback(snapshot),
                action: onSkipBackward
            )
            NowPlayingPlayButton(
                phase: snapshot.phase,
                enabled: canControlPlayback(snapshot),
                action: onTogglePlayback
            )
            NowPlayingTransportButton(
                symbol: "goforward.30",
                label: "前进 30 秒",
                enabled: canControlPlayback(snapshot),
                action: onSkipForward
            )
        }
        .fixedSize()
    }

    private func canControlPlayback(_ snapshot: PlaybackIdentitySnapshot) -> Bool {
        snapshot.isPlayable && snapshot.phase != .loading
    }
}

private struct NowPlayingOutputControl: View {
    @ObservedObject var output: PlaybackOutputSession
    let outputController: AudioPlaybackController
    let onSetVolume: (Double) -> Void
    let onCommitVolume: () -> Void

    @Environment(\.designPalette) private var palette
    @State private var isPresented = false

    var body: some View {
        Button("音量与输出", systemImage: speakerSymbol) {
            isPresented.toggle()
        }
        .labelStyle(.iconOnly)
        .buttonStyle(ToolIconButtonStyle())
        .frame(width: 32, height: 32)
        .accessibilityIdentifier("now-playing.output")
        .accessibilityValue("\(volumePercentage)%")
        .help("音量与输出")
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            outputPanel
        }
    }

    private var outputPanel: some View {
        VStack(alignment: .leading, spacing: DesignMetrics.space16) {
            HStack {
                Text("音量与输出")
                    .font(DesignTypography.sectionTitle)
                Spacer()
                Text("\(volumePercentage)%")
                    .font(DesignTypography.metadata.monospacedDigit())
                    .foregroundStyle(palette.textSecondary)
            }

            ToolSlider(
                "播放音量", value: volumeBinding, in: 0...1, onEditingChanged: volumeEditingChanged
            )
            .accessibilityIdentifier("now-playing.volume")
            .accessibilityLabel("播放音量")
            .accessibilityValue("\(volumePercentage)%")

            HStack(spacing: DesignMetrics.space8) {
                Text("输出设备")
                    .font(DesignTypography.body)
                Spacer()
                // AVRoutePickerView performs device discovery during its first layout.
                // Create it only when the user asks for output controls.
                NowPlayingRoutePicker(
                    player: outputController.routePlayer,
                    tintColor: NSColor(palette.textSecondary)
                )
                .frame(width: 24, height: 24)
                .accessibilityLabel("选择音频输出设备")
                .help("选择音频输出设备")
            }
        }
        .foregroundStyle(palette.textPrimary)
        .padding(DesignMetrics.space16)
        .frame(width: 248)
    }

    private var volumeBinding: Binding<Double> {
        Binding(
            get: { output.snapshot.volume },
            set: { onSetVolume($0) }
        )
    }

    private var volumePercentage: Int {
        Int((output.snapshot.volume * 100).rounded())
    }

    private var speakerSymbol: String {
        switch output.snapshot.volume {
        case ..<0.01: "speaker.slash.fill"
        case ..<0.45: "speaker.wave.1.fill"
        default: "speaker.wave.2.fill"
        }
    }

    private func volumeEditingChanged(_ editing: Bool) {
        if !editing {
            onCommitVolume()
        }
    }
}

private struct NowPlayingRoutePicker: NSViewRepresentable {
    let player: AVPlayer?
    let tintColor: NSColor

    func makeNSView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.isRoutePickerButtonBordered = false
        updateButtonColors(for: picker)
        picker.player = player
        return picker
    }

    func updateNSView(_ picker: AVRoutePickerView, context: Context) {
        if picker.player !== player {
            picker.player = player
        }
        updateButtonColors(for: picker)
    }

    private func updateButtonColors(for picker: AVRoutePickerView) {
        for state in [
            AVRoutePickerView.ButtonState.normal,
            .normalHighlighted,
            .active,
            .activeHighlighted,
        ] {
            picker.setRoutePickerButtonColor(tintColor, for: state)
        }
    }
}

private struct NowPlayingItemMenu: View {
    let item: AudioItem
    let onStartDownload: (AudioItem) -> Void
    let onCancelDownload: (UUID) -> Void
    @Environment(\.openURL) private var openURL
    @Environment(\.designPalette) private var palette

    var body: some View {
        Menu {
            Button {
                openURL(item.sourceURL)
            } label: {
                Label("打开来源", systemImage: "safari")
            }

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(item.sourceURL.absoluteString, forType: .string)
            } label: {
                Label("复制链接", systemImage: "doc.on.doc")
            }

            Divider()
            downloadAction
        } label: {
            Label("更多播放选项", systemImage: "ellipsis")
                .labelStyle(.iconOnly)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(palette.textSecondary)
                .frame(width: 32, height: 32)
        }
        .menuStyle(.button)
        .buttonStyle(ToolIconButtonStyle())
        .menuIndicator(.hidden)
        .accessibilityIdentifier("now-playing.more")
        .accessibilityLabel("更多播放选项")
        .help("更多播放选项")
    }

    @ViewBuilder
    private var downloadAction: some View {
        switch item.downloadState {
        case .notRequested:
            Button {
                onStartDownload(item)
            } label: {
                Label("下载", systemImage: "arrow.down.circle")
            }
        case .downloading:
            Button(role: .destructive) {
                onCancelDownload(item.id)
            } label: {
                Label("取消下载", systemImage: "xmark.circle")
            }
        case .available:
            Label("已下载", systemImage: "checkmark.circle")
        case .failed:
            Button {
                onStartDownload(item)
            } label: {
                Label("重新下载", systemImage: "arrow.clockwise")
            }
        }
    }
}

private struct NowPlayingDownloadProgress: View {
    @ObservedObject var session: DownloadSession
    let itemID: UUID

    @Environment(\.designPalette) private var palette

    var body: some View {
        if session.activeItemID == itemID {
            HStack(spacing: DesignMetrics.space8) {
                if let fraction {
                    ProgressView(value: fraction)
                        .progressViewStyle(.linear)
                        .accessibilityLabel("下载进度")
                        .accessibilityValue(
                            Text(fraction, format: .percent.precision(.fractionLength(0)))
                        )

                    Text(fraction, format: .percent.precision(.fractionLength(0)))
                        .font(DesignTypography.metadata)
                        .monospacedDigit()
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
                        .font(DesignTypography.metadata)
                        .monospacedDigit()
                        .foregroundStyle(palette.textSecondary)
                        .accessibilityLabel("下载速度")
                }
            }
            .accessibilityIdentifier("download.progress")
        }
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

private struct NowPlayingProgressControl: View {
    @ObservedObject var timeline: PlaybackTimelineSession
    let isPlayable: Bool
    let onSeek: (TimeInterval) -> Void

    @State private var isScrubbing = false
    @State private var draftTime: TimeInterval = 0
    @State private var optimisticTime: TimeInterval?
    @Environment(\.designPalette) private var palette

    var body: some View {
        VStack(spacing: DesignMetrics.space4) {
            ToolSlider(
                "播放进度", value: binding, in: 0...maximumDuration, onEditingChanged: editingChanged
            )
            .disabled(!isPlayable || timeline.snapshot.duration <= 0)
            .accessibilityIdentifier("now-playing.progress")
            .accessibilityLabel("播放进度")
            .help("拖动调整播放进度")

            HStack(alignment: .center, spacing: DesignMetrics.space8) {
                Text(PlaybackTimeFormatter.string(for: displayedTime))
                    .frame(width: 56, alignment: .leading)

                Spacer(minLength: DesignMetrics.space4)

                Text(
                    PlaybackTimeFormatter.remainingString(
                        current: displayedTime,
                        duration: timeline.snapshot.duration
                    )
                )
                .frame(width: 56, alignment: .trailing)
            }
            .font(DesignTypography.metadata)
            .monospacedDigit()
            .foregroundStyle(palette.textSecondary)
        }
        .onChange(of: timeline.snapshot.currentTime) { _, value in
            guard let optimisticTime, abs(value - optimisticTime) < 0.5 else { return }
            self.optimisticTime = nil
        }
    }

    private var maximumDuration: TimeInterval {
        max(timeline.snapshot.duration, 0.01)
    }

    private var displayedTime: TimeInterval {
        min(
            max(isScrubbing ? draftTime : (optimisticTime ?? timeline.snapshot.currentTime), 0),
            maximumDuration
        )
    }

    private var binding: Binding<TimeInterval> {
        Binding(
            get: { displayedTime },
            set: { value in
                draftTime = min(max(value, 0), maximumDuration)
                isScrubbing = true
            }
        )
    }

    private func editingChanged(_ isEditing: Bool) {
        if isEditing {
            optimisticTime = nil
            draftTime = displayedTime
            isScrubbing = true
        } else {
            let target = draftTime
            isScrubbing = false
            optimisticTime = target
            onSeek(target)
        }
    }

}

private struct NowPlayingRateMenu: View {
    let rate: Double
    let onSetRate: (Double) -> Void

    @Environment(\.designPalette) private var palette

    var body: some View {
        Menu {
            ForEach(AppPreferences.supportedPlaybackRates, id: \.self) { candidate in
                Button(rateLabel(candidate)) { onSetRate(candidate) }
            }
        } label: {
            Text(rateLabel(rate))
                .font(DesignTypography.bodyMedium)
                .foregroundStyle(palette.textPrimary)
                .frame(minWidth: 36, minHeight: 24)
        }
        .menuStyle(.button)
        .buttonStyle(ToolActionButtonStyle(kind: .secondary, compact: true))
        .menuIndicator(.hidden)
        .accessibilityIdentifier("now-playing.playback-rate")
        .accessibilityLabel("播放速度，当前 \(rateLabel(rate))")
        .help("播放速度")
    }

    private func rateLabel(_ rate: Double) -> String {
        "\(rate.formatted(.number.precision(.fractionLength(0...2))))×"
    }
}

private struct NowPlayingTransportButton: View {
    let symbol: String
    let label: String
    let enabled: Bool
    let action: () -> Void

    @Environment(\.designPalette) private var palette

    var body: some View {
        Button(action: action) {
            Label(label, systemImage: symbol)
                .labelStyle(.iconOnly)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(palette.textPrimary)
                .frame(width: 16, height: 16)
        }
        .buttonStyle(ToolIconButtonStyle())
        .disabled(!enabled)
        .accessibilityLabel(label)
        .accessibilityIdentifier("now-playing.\(symbol)")
        .help(label)
    }
}

private struct NowPlayingPlayButton: View {
    let phase: PlaybackPhase
    let enabled: Bool
    let action: () -> Void

    @Environment(\.designPalette) private var palette

    private var hasPlaybackIntent: Bool { phase.hasPlaybackIntent }
    private var isPreparing: Bool { phase == .loading || phase == .buffering }

    var body: some View {
        Button(action: action) {
            Group {
                if isPreparing {
                    ProgressView()
                        .controlSize(.small)
                        .tint(palette.surface)
                } else {
                    Label(
                        hasPlaybackIntent ? "暂停" : "播放",
                        systemImage: hasPlaybackIntent ? "pause.fill" : "play.fill"
                    )
                    .labelStyle(.iconOnly)
                    .font(.system(size: 18, weight: .semibold))
                }
            }
            .frame(width: 24, height: 24)
        }
        .buttonStyle(ToolActionButtonStyle(kind: .primary))
        .disabled(!enabled)
        .accessibilityIdentifier("now-playing.play")
        .accessibilityLabel(hasPlaybackIntent ? "暂停" : "播放")
        .accessibilityValue(phase.isPlaying ? "正在播放" : "未播放")
        .help(hasPlaybackIntent ? "暂停" : "播放")
        .keyboardShortcut(.space, modifiers: [])
    }
}
