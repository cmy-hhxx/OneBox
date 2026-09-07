import AppKit
import OneBoxDesignSystem
import SwiftUI

struct PodPinLibraryView: View {
    @EnvironmentObject private var store: PodPinStore
    @EnvironmentObject private var navigator: AppNavigator
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.oneBoxAccessibilityReduceMotionOverride) private var reduceMotionOverride
    @Environment(\.designPalette) private var palette
    @State private var sheet: LibrarySheet?
    @State private var folderPendingDeletion: LibraryFolderNode?
    @State private var folderDeletionReason: String?
    @State private var itemPendingDeletion: LibraryItemRow?
    @State private var selectedItemID: UUID?

    private var reduceMotion: Bool {
        reduceMotionOverride ?? systemReduceMotion
    }

    var body: some View {
        LibrarySessionObserver(session: store.librarySession) {
            switch store.startupPhase {
            case .loading:
                ProgressView {
                    Text("正在打开本地资料库…")
                        .font(DesignTypography.body)
                        .foregroundStyle(palette.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                LibraryUnavailableView(message: message) {
                    store.performLibraryOperation { await store.retryStart() }
                }
            case .ready:
                libraryWorkspace
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.background)
        .sheet(item: $sheet) { sheet in
            sheetView(for: sheet)
        }
        .background(
            ImportVerificationRoute(
                session: store.importSession,
                selectedFolderID: store.selectedFolderID,
                onPresent: openImport(in:)
            )
        )
        .onExitCommand {
            navigator.handleExitCommand(reduceMotion: reduceMotion)
        }
    }

    @ViewBuilder
    private func sheetView(for sheet: LibrarySheet) -> some View {
        switch sheet {
        case .folderEditor(let request):
            FolderEditorSheet(
                request: request,
                folderTree: store.folderTree(),
                onSave: { name, parentID, completion in
                    saveFolderEditor(
                        request,
                        name: name,
                        parentID: parentID,
                        completion: completion
                    )
                }
            )
        case .moveFolder(let folder):
            FolderDestinationSheet(
                title: "移动“\(folder.name)”",
                folders: store.folderTree(),
                excluding: excludedFolderDestinations(for: folder.id),
                selectedDestination: folder.parentID
            ) { parentID in
                store.performLibraryOperation { await store.moveFolder(folder.id, to: parentID) }
            }
        case .moveItem(let item):
            FolderDestinationSheet(
                title: "移动“\(item.title)”",
                folders: store.folderTree(),
                excluding: [item.folderID],
                selectedDestination: item.folderID,
                includesLibraryRoot: false
            ) { destinationID in
                guard let destinationID else { return }
                store.performLibraryOperation {
                    await store.moveItem(item.id, to: destinationID)
                }
            }
        }
    }

    private var importEntryContext: ImportEntryContext {
        navigator.importContext
            ?? ImportEntryContext(destinationFolderID: store.selectedFolderID)
    }

    private var nowPlayingWorkspace: some View {
        NowPlayingView(
            queueIsPresented: $navigator.isQueuePresented,
            playbackIdentity: store.playbackPresentation.identity,
            playbackTimeline: store.playbackPresentation.timeline,
            output: store.playbackPresentation.output,
            queue: store.playbackQueue.session,
            downloadSession: store.downloadSession,
            outputController: store.playbackOutputController,
            backLabel: nowPlayingBackLabel,
            onClose: { navigator.closeNowPlaying(reduceMotion: reduceMotion) },
            onTogglePlayback: { store.togglePlayback() },
            onSkipBackward: { store.skipBackward() },
            onSkipForward: { store.skipForward() },
            onSeek: { store.seek(to: $0) },
            onSetRate: { store.setPlaybackRate($0) },
            onSetVolume: { store.setPlaybackVolume($0) },
            onCommitVolume: { store.commitPlaybackVolume() },
            onStartDownload: { store.startDownload($0) },
            onCancelDownload: { store.cancelDownload(for: $0) },
            onPlayQueueItem: { store.playQueuedItem($0) },
            onRemoveQueueItem: { store.removeQueueItem($0) },
            onMoveQueueItem: { store.moveQueueItem($0, to: $1) },
            onClearQueue: { store.clearPlaybackQueue() },
            onRetryQueue: { store.retryQueuePlayback() },
            artworkURL: { store.artworkURL(for: $0) }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var nowPlayingBackLabel: String {
        if case .some(.importLink) = navigator.routeStack.dropLast().last {
            "返回导入"
        } else {
            "返回资料库"
        }
    }

    private var libraryWorkspace: some View {
        LibraryWorkspaceView(
            folders: store.folderTree(),
            selectedCollection: $store.selectedCollection,
            routeStack: navigator.routeStack,
            routeDirection: navigator.routeDirection,
            selectedFolderTitle: store.selectedFolderTitle(),
            items: store.visibleItems(),
            itemsPhase: store.itemsPhase,
            canLoadMoreItems: store.canLoadMoreItems,
            selectedItemID: $selectedItemID,
            currentItemID: store.currentItem?.id,
            isPlaying: store.isPlaying,
            downloadSession: store.downloadSession,
            playbackTimeline: store.playbackPresentation.timeline,
            importContent: ImportWorkspaceView(
                store: store,
                entryContext: importEntryContext,
                draft: $navigator.importDraft,
                isActive: isImportRouteActive,
                onImportSucceeded: { importedItemID in
                    selectedItemID = importedItemID
                },
                onRequestFolderEditor: { request in
                    sheet = .folderEditor(request)
                }
            )
            .id(importEntryContext.id),
            nowPlayingContent: nowPlayingWorkspace,
            compactPlayerContent: CompactPlayerBar(
                identity: store.playbackPresentation.identity,
                queue: store.playbackQueue.session,
                timeline: store.playbackPresentation.timeline,
                onTogglePlayback: { store.togglePlayback() },
                onRetryPlayback: { store.retryPlayback() },
                onSkipBackward: { store.skipBackward() },
                onSkipForward: { store.skipForward() },
                onSeek: { store.seek(to: $0) },
                onSetRate: { store.setPlaybackRate($0) },
                onImport: { openImport(in: store.selectedFolderID) },
                onOpenQueue: { navigator.showQueue(reduceMotion: reduceMotion) }
            ),
            notice: currentNotice,
            onRequestFolderEditor: { request in
                sheet = .folderEditor(request)
            },
            onFolderAction: handleFolderAction,
            onItemAction: handleItemAction,
            onRetryItems: store.retrySelectedFolder,
            onLoadMoreItems: store.loadMoreItems,
            onOpenImport: openImport(in:),
            onShowLibrary: { navigator.showLibraryContent(reduceMotion: reduceMotion) },
            onShowNowPlaying: { navigator.showNowPlaying(reduceMotion: reduceMotion) },
            onCopyNoticeDetails: copyNoticeDetails,
            onDismissNotice: dismissNotice
        )
        .confirmationDialog(
            "删除文件夹？",
            isPresented: Binding(
                get: { folderPendingDeletion != nil },
                set: { if !$0 { folderPendingDeletion = nil } }
            ),
            presenting: folderPendingDeletion
        ) { folder in
            Button("删除", role: .destructive) {
                folderPendingDeletion = nil
                store.performLibraryOperation { await store.deleteFolder(folder.id) }
            }
            Button("取消", role: .cancel) { folderPendingDeletion = nil }
        } message: { folder in
            Text("“\(folder.name)”为空，删除后无法恢复。")
        }
        .confirmationDialog(
            "删除这条音频？",
            isPresented: Binding(
                get: { itemPendingDeletion != nil },
                set: { if !$0 { itemPendingDeletion = nil } }
            ),
            presenting: itemPendingDeletion
        ) { item in
            Button("删除", role: .destructive) {
                itemPendingDeletion = nil
                store.performLibraryOperation { await store.deleteItem(item.id) }
            }
            Button("取消", role: .cancel) { itemPendingDeletion = nil }
        } message: { item in
            Text("“\(item.title)”及其离线音频（如有）将被移除。")
        }
    }

    private var isImportRouteActive: Bool {
        if case .importLink = navigator.currentRoute { return true }
        return false
    }

    private func openImport(in folderID: UUID) {
        navigator.openImport(in: folderID, reduceMotion: reduceMotion)
    }

    private var currentNotice: PodPinNotice? {
        if let folderDeletionReason {
            return PodPinNotice(
                id: "folder-deletion",
                title: "无法删除文件夹",
                message: folderDeletionReason
            )
        }
        return store.userFacingError.map(PodPinNotice.init(error:))
    }

    private func copyNoticeDetails(_ details: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(details, forType: .string)
    }

    private func dismissNotice() {
        if folderDeletionReason != nil {
            folderDeletionReason = nil
        } else {
            store.dismissError()
        }
    }

    private func saveFolderEditor(
        _ request: FolderEditorRequest,
        name: String,
        parentID: UUID?,
        completion: @escaping FolderEditorSheet.SaveCompletion
    ) {
        store.performLibraryOperation {
            switch request.operation {
            case .create:
                guard
                    let created = await store.createFolder(
                        named: name,
                        parentID: parentID,
                        reportError: false
                    )
                else {
                    guard !Task.isCancelled else { return }
                    completion("无法创建，请检查名称或位置是否重复。")
                    return
                }
                guard !Task.isCancelled else { return }
                store.selectedCollection = .folder(created.id)
                request.onSaved(created)
                completion(nil)
            case .rename(let folderID):
                guard await store.renameFolder(folderID, to: name, reportError: false) else {
                    guard !Task.isCancelled else { return }
                    completion("无法保存，请检查名称是否重复。")
                    return
                }
                guard !Task.isCancelled else { return }
                if let renamed = store.folders.first(where: { $0.id == folderID }) {
                    request.onSaved(renamed)
                }
                completion(nil)
            }
        }
    }

    private func handleFolderAction(_ node: LibraryFolderNode, _ action: LibraryFolderAction) {
        switch action {
        case .move:
            let parentID = store.folders.first(where: { $0.id == node.id })?.parentID
            sheet = .moveFolder(node.withParentID(parentID))
        case .delete:
            store.performLibraryOperation {
                if let reason = await store.folderDeletionReason(node.id) {
                    folderDeletionReason = reason
                } else if !Task.isCancelled {
                    folderPendingDeletion = node
                }
            }
        }
    }

    private func excludedFolderDestinations(for folderID: UUID) -> Set<UUID> {
        let childrenByParent = Dictionary(grouping: store.folders, by: \.parentID)
        var excluded: Set<UUID> = [folderID]
        var frontier = [folderID]
        while let parent = frontier.popLast() {
            let children = (childrenByParent[parent] ?? []).map(\.id)
            excluded.formUnion(children)
            frontier.append(contentsOf: children)
        }
        return excluded
    }

    private func handleItemAction(_ row: LibraryItemRow, _ action: LibraryItemAction) {
        switch action {
        case .playNow:
            guard let item = store.items.first(where: { $0.id == row.id }) else { return }
            store.playNow(item)
        case .togglePlayback:
            guard let item = store.items.first(where: { $0.id == row.id }) else { return }
            if store.currentItem?.id == item.id, store.isPlaying {
                store.pausePlayback()
            } else {
                store.playNow(item)
            }
        case .enqueueNext:
            guard let item = store.items.first(where: { $0.id == row.id }) else { return }
            store.enqueueNext(item)
        case .enqueueLast:
            guard let item = store.items.first(where: { $0.id == row.id }) else { return }
            store.enqueueLast(item)
        case .move:
            sheet = .moveItem(row)
        case .download, .retryDownload:
            guard let item = store.items.first(where: { $0.id == row.id }) else { return }
            store.startDownload(item)
        case .cancelDownload:
            store.cancelDownload(for: row.id)
        case .delete:
            itemPendingDeletion = row
        }
    }
}

@MainActor
private struct CompactPlayerBar: View {
    @ObservedObject var identity: PlaybackIdentitySession
    @ObservedObject var queue: PlaybackQueueSession
    let timeline: PlaybackTimelineSession
    let onTogglePlayback: () -> Void
    let onRetryPlayback: () -> Void
    let onSkipBackward: () -> Void
    let onSkipForward: () -> Void
    let onSeek: (TimeInterval) -> Void
    let onSetRate: (Double) -> Void
    let onImport: () -> Void
    let onOpenQueue: () -> Void

    @Environment(\.designPalette) private var palette

    var body: some View {
        HStack(spacing: DesignMetrics.space8) {
            identityLabel
            primaryControl
            jumpMenu
            CompactPlaybackSlider(
                timeline: timeline,
                phase: identity.snapshot.phase,
                isPlayable: identity.snapshot.isPlayable,
                onSeek: onSeek
            )
            .frame(minWidth: 130, maxWidth: .infinity)
            rateControl
            queueButton
        }
        .frame(maxWidth: .infinity, minHeight: 56)
        .padding(.vertical, DesignMetrics.space4)
        .background(palette.background)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var identityLabel: some View {
        if let item = identity.snapshot.item {
            VStack(alignment: .leading, spacing: DesignMetrics.space4) {
                Text(item.title)
                    .font(DesignTypography.bodyMedium)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                Text(item.author ?? "未知作者")
                    .font(DesignTypography.metadata)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
            }
            .frame(minWidth: 100, idealWidth: 144, maxWidth: 180, alignment: .leading)
            .accessibilityElement(children: .combine)
        } else {
            Button(action: onImport) {
                VStack(alignment: .leading, spacing: DesignMetrics.space4) {
                    Text("暂无播放内容")
                        .font(DesignTypography.bodyMedium)
                        .foregroundStyle(palette.textPrimary)
                    Text("导入公开链接开始收听")
                        .font(DesignTypography.metadata)
                        .foregroundStyle(palette.accent)
                }
                .frame(minWidth: 100, idealWidth: 144, maxWidth: 180, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("导入公开链接开始收听")
            .help("打开导入")
        }
    }

    @ViewBuilder
    private var primaryControl: some View {
        if identity.snapshot.phase == .loading {
            ProgressView()
                .controlSize(.small)
                .frame(
                    width: DesignMetrics.titlebarControlSize,
                    height: DesignMetrics.titlebarControlSize
                )
                .accessibilityLabel("正在加载音频")
        } else {
            Button(action: primaryAction) {
                Image(systemName: primarySymbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.accent)
                    .frame(
                        width: DesignMetrics.titlebarControlSize,
                        height: DesignMetrics.titlebarControlSize
                    )
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(!canUsePrimaryControl)
            .accessibilityIdentifier("compact-player.play")
            .accessibilityLabel(primaryLabel)
            .accessibilityValue(identity.snapshot.isPlaying ? "正在播放" : "未播放")
            .help(primaryLabel)
        }
    }

    private var jumpMenu: some View {
        Menu {
            Button("后退 15 秒", systemImage: "gobackward.15", action: onSkipBackward)
            Button("前进 30 秒", systemImage: "goforward.30", action: onSkipForward)
        } label: {
            Image(systemName: "arrow.left.arrow.right")
                .foregroundStyle(palette.textSecondary)
                .frame(
                    width: DesignMetrics.titlebarControlSize,
                    height: DesignMetrics.titlebarControlSize
                )
                .contentShape(.rect)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .disabled(!canUseTransportControls)
        .accessibilityLabel("播放跳转")
        .help("后退或前进")
    }

    private var rateControl: some View {
        Button {
            onSetRate(AppPreferences.nextPlaybackRate(after: identity.snapshot.rate))
        } label: {
            Text(rateLabel)
                .font(DesignTypography.metadata.monospacedDigit())
                .foregroundStyle(palette.textPrimary)
                .frame(width: 40, height: DesignMetrics.titlebarControlSize)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("播放速度")
        .accessibilityValue(rateLabel)
        .help("切换播放速度")
    }

    private var queueButton: some View {
        Button(action: onOpenQueue) {
            HStack(spacing: DesignMetrics.space4) {
                Image(systemName: "text.line.first.and.arrowtriangle.forward")
                Text("\(queue.count)")
                    .font(DesignTypography.metadata.monospacedDigit())
            }
            .foregroundStyle(palette.textSecondary)
            .frame(width: 44, height: DesignMetrics.titlebarControlSize)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("打开正在播放与队列")
        .accessibilityValue("\(queue.count) 项待播")
        .help("打开正在播放与队列")
    }

    private var canUseTransportControls: Bool {
        identity.snapshot.isPlayable
            && [.paused, .playing, .finished].contains(identity.snapshot.phase)
    }

    private var canUsePrimaryControl: Bool {
        identity.snapshot.isPlayable
            && identity.snapshot.phase != .loading
            && identity.snapshot.phase != .replayPending
    }

    private var isFailed: Bool {
        if case .failed = identity.snapshot.phase { true } else { false }
    }

    private var primaryAction: () -> Void {
        isFailed ? onRetryPlayback : onTogglePlayback
    }

    private var primarySymbol: String {
        if isFailed { return "arrow.clockwise" }
        return identity.snapshot.phase.hasPlaybackIntent ? "pause.fill" : "play.fill"
    }

    private var primaryLabel: String {
        if isFailed { return "重试播放" }
        return identity.snapshot.phase.hasPlaybackIntent ? "暂停" : "播放"
    }

    private var rateLabel: String {
        "\(identity.snapshot.rate.formatted(.number.precision(.fractionLength(0...2))))×"
    }
}

@MainActor
private struct CompactPlaybackSlider: View {
    @ObservedObject var timeline: PlaybackTimelineSession
    let phase: PlaybackPhase
    let isPlayable: Bool
    let onSeek: (TimeInterval) -> Void

    @State private var isScrubbing = false
    @State private var draftTime: TimeInterval = 0
    @State private var optimisticTime: TimeInterval?
    @Environment(\.designPalette) private var palette

    var body: some View {
        HStack(spacing: DesignMetrics.space4) {
            Text(PlaybackTimeFormatter.string(for: displayedTime))
                .font(DesignTypography.metadata.monospacedDigit())
                .foregroundStyle(palette.textSecondary)
                .frame(minWidth: 36, alignment: .trailing)

            Slider(value: seekBinding, in: 0...validDuration, onEditingChanged: updateScrubbing)
                .controlSize(.small)
                .tint(palette.accent)
                .disabled(!canSeek)
                .accessibilityLabel("播放进度")
                .accessibilityValue(
                    "\(PlaybackTimeFormatter.string(for: displayedTime))，共 \(PlaybackTimeFormatter.string(for: validDuration))"
                )

            Text(PlaybackTimeFormatter.string(for: validDuration))
                .font(DesignTypography.metadata.monospacedDigit())
                .foregroundStyle(palette.textSecondary)
                .frame(minWidth: 36, alignment: .leading)
        }
        .onChange(of: timeline.snapshot.currentTime) { _, currentTime in
            guard let optimisticTime, abs(currentTime - optimisticTime) < 0.5 else { return }
            self.optimisticTime = nil
        }
    }

    private var validDuration: TimeInterval {
        let duration = timeline.snapshot.duration
        return duration.isFinite && duration > 0 ? duration : 0
    }

    private var displayedTime: TimeInterval {
        let proposed =
            isScrubbing
            ? draftTime
            : (optimisticTime ?? timeline.snapshot.currentTime)
        return min(max(proposed, 0), validDuration)
    }

    private var canSeek: Bool {
        isPlayable
            && validDuration > 0
            && [.paused, .playing, .finished].contains(phase)
    }

    private var seekBinding: Binding<TimeInterval> {
        Binding(
            get: { displayedTime },
            set: { proposedTime in
                draftTime = min(max(proposedTime, 0), validDuration)
                isScrubbing = true
            }
        )
    }

    private func updateScrubbing(_ editing: Bool) {
        if editing {
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

/// Keeps library refreshes scoped to the library session instead of forwarding
/// its change notifications through the whole application store.
private struct LibrarySessionObserver<Content: View>: View {
    @ObservedObject var session: LibrarySession
    private let content: () -> Content

    init(
        session: LibrarySession,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.session = session
        self.content = content
    }

    var body: some View {
        // Reading the session here is intentional: this child is the one
        // subscription boundary that re-evaluates workspace values on a
        // library change.
        let _ = session.startupPhase
        let _ = session.itemsPhase
        let _ = session.folders
        let _ = session.items
        content()
    }
}

/// Import view state owns its own rendering. This small observer only turns a
/// verification request into the existing in-window import route.
private struct ImportVerificationRoute: View {
    @ObservedObject var session: ImportSession
    let selectedFolderID: UUID
    let onPresent: (UUID) -> Void

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onChange(of: session.verificationRequest) { _, request in
                if request != nil {
                    onPresent(selectedFolderID)
                }
            }
    }
}

private enum LibrarySheet: Identifiable {
    case folderEditor(FolderEditorRequest)
    case moveFolder(LibraryFolderMoveTarget)
    case moveItem(LibraryItemRow)

    var id: String {
        switch self {
        case .folderEditor(let request): "folder-editor-\(request.id.uuidString)"
        case .moveFolder(let folder): "move-folder-\(folder.id.uuidString)"
        case .moveItem(let item): "move-item-\(item.id.uuidString)"
        }
    }
}

private struct LibraryFolderMoveTarget {
    let id: UUID
    let name: String
    let parentID: UUID?
}

extension LibraryFolderNode {
    fileprivate func withParentID(_ parentID: UUID?) -> LibraryFolderMoveTarget {
        LibraryFolderMoveTarget(id: id, name: name, parentID: parentID)
    }
}

private struct FolderDestinationSheet: View {
    let title: String
    let folders: [LibraryFolderNode]
    let excluding: Set<UUID>
    let selectedDestination: UUID?
    var includesLibraryRoot = true
    let onConfirm: (UUID?) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.designPalette) private var palette
    @State private var destinationID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: DesignMetrics.space16) {
            Text(title)
                .font(DesignTypography.sectionTitle)
                .foregroundStyle(palette.textPrimary)

            Text("目标文件夹")
                .font(DesignTypography.bodyMedium)
                .foregroundStyle(palette.textPrimary)

            LibraryFolderTreePicker(
                folders: folders,
                excluding: excluding,
                selectedFolderID: destinationID,
                includesLibraryRoot: includesLibraryRoot,
                onSelect: { destinationID = $0 }
            )
            .frame(minHeight: 180, maxHeight: 300)

            HStack {
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer(minLength: DesignMetrics.space8)
                Button("移动") {
                    onConfirm(destinationID)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .font(DesignTypography.body)
        }
        .padding(DesignMetrics.space24)
        .frame(width: 420)
        .background(palette.background)
        .onAppear { destinationID = selectedDestination }
    }
}

private struct LibraryUnavailableView: View {
    let message: String
    let retry: () -> Void

    @Environment(\.designPalette) private var palette

    var body: some View {
        VStack(spacing: DesignMetrics.space12) {
            Image(systemName: "externaldrive.badge.exclamationmark")
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(palette.negative)
                .accessibilityHidden(true)
            Text("无法打开本地资料库")
                .font(DesignTypography.sectionTitle)
                .foregroundStyle(palette.textPrimary)
            Text(message)
                .font(DesignTypography.body)
                .foregroundStyle(palette.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
            Button("重试", action: retry)
                .buttonStyle(.borderedProminent)
        }
        .padding(DesignMetrics.space24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
