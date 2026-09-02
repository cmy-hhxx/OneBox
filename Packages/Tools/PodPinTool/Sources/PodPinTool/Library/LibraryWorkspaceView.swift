import Foundation
import OneBoxDesignSystem
import SwiftUI

/// UI-only folder representation. The store adapts persisted `LibraryFolder`
/// records into this tree, so the view never takes a database dependency.
struct LibraryFolderNode: Identifiable, Hashable {
    let id: UUID
    let folderID: UUID
    let name: String
    let isSystemFolder: Bool
    let children: [LibraryFolderNode]

    init(
        id: UUID,
        folderID: UUID = LibraryFolder.inboxID,
        name: String,
        isSystemFolder: Bool = false,
        children: [LibraryFolderNode] = []
    ) {
        self.id = id
        self.folderID = folderID
        self.name = name
        self.isSystemFolder = isSystemFolder
        self.children = children
    }

    var outlineChildren: [LibraryFolderNode]? {
        children.isEmpty ? nil : children
    }
}

/// UI-only row representation for the selected folder's audio items.
struct LibraryItemRow: Identifiable, Hashable {
    enum StorageState: Hashable {
        case online
        case downloading
        case downloaded
        case downloadFailed

        var label: String {
            switch self {
            case .online: "在线"
            case .downloading: "下载中"
            case .downloaded: "已下载"
            case .downloadFailed: "下载失败"
            }
        }

        var symbolName: String {
            switch self {
            case .online: "dot.radiowaves.left.and.right"
            case .downloading: "arrow.down.circle"
            case .downloaded: "checkmark.circle.fill"
            case .downloadFailed: "exclamationmark.triangle.fill"
            }
        }
    }

    let id: UUID
    let folderID: UUID
    let title: String
    let author: String?
    let sourceName: String
    let duration: TimeInterval?
    let importedAt: Date
    let storageState: StorageState
    let progress: TimeInterval
    let listeningHistory: ListeningHistory
    let artworkURL: URL?

    init(
        id: UUID,
        folderID: UUID = LibraryFolder.inboxID,
        title: String,
        author: String? = nil,
        sourceName: String,
        duration: TimeInterval? = nil,
        importedAt: Date,
        storageState: StorageState,
        progress: TimeInterval = 0,
        listeningHistory: ListeningHistory = ListeningHistory(),
        artworkURL: URL? = nil
    ) {
        self.id = id
        self.folderID = folderID
        self.title = title
        self.author = author
        self.sourceName = sourceName
        self.duration = duration
        self.importedAt = importedAt
        self.storageState = storageState
        self.progress = progress
        self.listeningHistory = listeningHistory
        self.artworkURL = artworkURL
    }
}

enum LibraryFolderAction {
    case move
    case delete
}

enum LibraryItemAction {
    case playNow
    case togglePlayback
    case enqueueNext
    case enqueueLast
    case move
    case delete
    case download
    case retryDownload
    case cancelDownload
}

/// The library lives inside OneBox's existing host navigation. Its own
/// destinations stay in one content region beneath a compact, persistent bar.
struct LibraryWorkspaceView<
    ImportContent: View,
    SettingsContent: View,
    NowPlayingContent: View,
    CompactPlayerContent: View
>: View {
    let folders: [LibraryFolderNode]
    @Binding var selectedCollection: LibraryCollection
    @Binding var destination: LibraryDestination
    let isSettingsPresented: Bool
    let selectedFolderTitle: String?
    let items: [LibraryItemRow]
    let itemsPhase: LibraryItemsPhase
    let canLoadMoreItems: Bool
    @Binding var selectedItemID: UUID?
    let currentItemID: UUID?
    let isPlaying: Bool
    let downloadSession: DownloadSession
    let playbackTimeline: PlaybackTimelineSession
    let importContent: ImportContent
    let settingsContent: SettingsContent
    let nowPlayingContent: NowPlayingContent
    let compactPlayerContent: CompactPlayerContent
    let onRequestFolderEditor: (FolderEditorRequest) -> Void
    let onFolderAction: (LibraryFolderNode, LibraryFolderAction) -> Void
    let onItemAction: (LibraryItemRow, LibraryItemAction) -> Void
    let onRetryItems: () -> Void
    let onLoadMoreItems: () -> Void
    let onShowNowPlaying: () -> Void
    let onToggleSettings: () -> Void
    let onCloseSettings: () -> Void

    @Environment(\.designPalette) private var palette
    @State private var isCollectionPickerPresented = false
    @AccessibilityFocusState private var isCollectionPickerButtonFocused: Bool
    @AccessibilityFocusState private var isSettingsButtonFocused: Bool

    private var selectedFolderID: UUID {
        selectedCollection.defaultImportFolderID
    }

    private var selectedFolderSelectionID: UUID? {
        guard case .folder(let folderID) = selectedCollection else { return nil }
        return folderID
    }

    private var selectedFolder: LibraryFolderNode? {
        guard let selectedFolderSelectionID else { return nil }
        return folderNode(withID: selectedFolderSelectionID, in: folders)
    }

    private var currentCollectionTitle: String {
        selectedFolderTitle ?? selectedCollection.title
    }

    private var isImportDestination: Bool {
        if case .importLink = destination { return true }
        return false
    }

    var body: some View {
        HStack(spacing: DesignMetrics.space12) {
            VStack(spacing: 0) {
                workspaceToolbar
                    .padding(.bottom, DesignMetrics.space8)
                destinationPane
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if destination != .nowPlaying {
                    Divider()
                    compactPlayerContent
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            if isSettingsPresented {
                ToolInspectorPanel("设置", closeLabel: "关闭设置", close: closeSettings) {
                    settingsContent
                }
                .tint(palette.accent)
                .frame(width: DesignMetrics.inspectorWidth)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(palette.background)
        .onChange(of: selectedCollection) { _, _ in
            destination = .library
        }
        .onChange(of: items) { _, refreshedItems in
            guard let selectedItemID,
                !refreshedItems.contains(where: { $0.id == selectedItemID })
            else { return }
            self.selectedItemID = nil
        }
    }

    private var workspaceToolbar: some View {
        ViewThatFits(in: .horizontal) {
            fullWorkspaceToolbar
                .frame(minWidth: 460)

            compactWorkspaceToolbar
        }
    }

    private var fullWorkspaceToolbar: some View {
        HStack(spacing: DesignMetrics.space8) {
            collectionSelectionMenu
            folderManagementMenu

            Spacer(minLength: 0)

            toolbarDestinationButton(
                "导入",
                systemImage: "link.badge.plus",
                isActive: isImportDestination,
                accessibilityIdentifier: "workspace.import"
            ) {
                openImportForSelectedFolder()
            }

            toolbarDestinationButton(
                "正在播放",
                systemImage: "waveform",
                isActive: destination == .nowPlaying,
                accessibilityIdentifier: "workspace.now-playing",
                action: onShowNowPlaying
            )

            toolbarDestinationButton(
                "设置",
                systemImage: "gearshape",
                isActive: isSettingsPresented,
                accessibilityIdentifier: "workspace.settings"
            ) {
                toggleSettings()
            }
            .accessibilityFocused($isSettingsButtonFocused)
        }
        .font(DesignTypography.bodyMedium)
        .controlSize(.regular)
        .frame(
            maxWidth: .infinity,
            minHeight: DesignMetrics.titlebarControlSize,
            alignment: .leading
        )
    }

    private var compactWorkspaceToolbar: some View {
        HStack(spacing: DesignMetrics.space4) {
            collectionSelectionMenu
                .frame(minWidth: 132, maxWidth: .infinity, alignment: .leading)
            folderManagementMenu

            Spacer(minLength: 0)

            toolbarDestinationButton(
                "导入",
                systemImage: "link.badge.plus",
                isActive: isImportDestination,
                accessibilityIdentifier: "workspace.import"
            ) {
                openImportForSelectedFolder()
            }

            compactToolbarDestinationButton(
                "正在播放",
                systemImage: "waveform",
                isActive: destination == .nowPlaying,
                accessibilityIdentifier: "workspace.now-playing",
                action: onShowNowPlaying
            )

            compactToolbarDestinationButton(
                "设置",
                systemImage: "gearshape",
                isActive: isSettingsPresented,
                accessibilityIdentifier: "workspace.settings",
                action: toggleSettings
            )
            .accessibilityFocused($isSettingsButtonFocused)
        }
        .font(DesignTypography.bodyMedium)
        .controlSize(.regular)
        .frame(
            maxWidth: .infinity,
            minHeight: DesignMetrics.titlebarControlSize,
            alignment: .leading
        )
    }

    private var collectionSelectionMenu: some View {
        Button {
            isCollectionPickerButtonFocused = false
            isCollectionPickerPresented = true
        } label: {
            HStack(spacing: DesignMetrics.space8) {
                Text(currentCollectionTitle)
                    .font(DesignTypography.bodyMedium)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
                Image(systemName: "chevron.down")
                    .font(DesignTypography.metadata)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(palette.textPrimary)
            .padding(.horizontal, DesignMetrics.space8)
            .frame(
                minWidth: 132,
                maxWidth: 220,
                minHeight: DesignMetrics.titlebarControlSize,
                alignment: .leading
            )
            .background(palette.surface, in: .rect(cornerRadius: DesignMetrics.cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: DesignMetrics.cornerRadius)
                    .strokeBorder(palette.border, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityFocused($isCollectionPickerButtonFocused)
        .popover(isPresented: $isCollectionPickerPresented, arrowEdge: .bottom) {
            LibraryCollectionPickerPanel(
                folders: folders,
                selectedCollection: selectedCollection,
                onSelect: selectCollection
            )
        }
        .accessibilityLabel("选择资料集合或文件夹")
        .accessibilityValue(currentCollectionTitle)
        .help("选择资料集合或文件夹")
    }

    private var folderManagementMenu: some View {
        Menu {
            Button("新建根文件夹") {
                requestFolderCreation(parentID: nil, source: .sidebar)
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
            .accessibilityIdentifier("library.create-folder")

            if let selectedFolder {
                Button("新建子文件夹") {
                    requestFolderCreation(parentID: selectedFolder.id, source: .folderMenu)
                }

                if !selectedFolder.isSystemFolder {
                    Divider()
                    Button("重命名") {
                        onRequestFolderEditor(
                            FolderEditorRequest(
                                operation: .rename(folderID: selectedFolder.id),
                                source: .folderMenu,
                                initialName: selectedFolder.name
                            )
                        )
                    }
                    Button("移动到…") {
                        onFolderAction(selectedFolder, .move)
                    }
                    Divider()
                    Button("删除", role: .destructive) {
                        onFolderAction(selectedFolder, .delete)
                    }
                }
            }
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
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .accessibilityLabel("管理文件夹")
        .accessibilityValue(selectedFolder?.name ?? "资料库")
        .accessibilityIdentifier(
            selectedFolder.map { "library.folder-actions.\($0.id.uuidString)" }
                ?? "library.folder-actions"
        )
        .help("管理文件夹")
    }

    private func toolbarDestinationButton(
        _ title: String,
        systemImage: String,
        isActive: Bool,
        accessibilityIdentifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(title, systemImage: systemImage, action: action)
            .buttonStyle(.borderless)
            .font(DesignTypography.bodyMedium)
            .foregroundStyle(palette.textPrimary)
            .padding(.horizontal, DesignMetrics.space4)
            .frame(minHeight: DesignMetrics.titlebarControlSize)
            .background(
                isActive ? palette.selection : palette.background,
                in: .rect(cornerRadius: DesignMetrics.cornerRadius)
            )
            .accessibilityValue(isActive ? "已打开" : "未打开")
            .accessibilityIdentifier(accessibilityIdentifier)
            .help(title)
    }

    private func compactToolbarDestinationButton(
        _ title: String,
        systemImage: String,
        isActive: Bool,
        accessibilityIdentifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(DesignTypography.bodyMedium)
                .frame(
                    width: DesignMetrics.titlebarControlSize,
                    height: DesignMetrics.titlebarControlSize
                )
                .contentShape(.rect)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(palette.textPrimary)
        .background(
            isActive ? palette.selection : palette.background,
            in: .rect(cornerRadius: DesignMetrics.cornerRadius)
        )
        .accessibilityLabel(title)
        .accessibilityValue(isActive ? "已打开" : "未打开")
        .accessibilityIdentifier(accessibilityIdentifier)
        .help(title)
    }

    private func selectCollection(_ collection: LibraryCollection) {
        selectedItemID = nil
        selectedCollection = collection
        destination = .library
        restoreCollectionPickerFocus()
    }

    private func requestFolderCreation(
        parentID: UUID?,
        source: FolderEditorRequest.Source
    ) {
        onRequestFolderEditor(
            FolderEditorRequest(
                operation: .create,
                source: source,
                defaultParentID: parentID
            )
        )
    }

    private func folderNode(
        withID folderID: UUID,
        in nodes: [LibraryFolderNode]
    ) -> LibraryFolderNode? {
        for node in nodes {
            if node.id == folderID {
                return node
            }
            if let match = folderNode(withID: folderID, in: node.children) {
                return match
            }
        }
        return nil
    }

    @ViewBuilder
    private var destinationPane: some View {
        switch destination {
        case .library:
            libraryContent
        case .importLink:
            importContent
        case .nowPlaying:
            nowPlayingContent
        }
    }

    @ViewBuilder
    private var libraryContent: some View {
        switch itemsPhase {
        case .idle, .loading:
            LibraryStatusView(
                title: "正在载入音频",
                message: "正在打开“\(currentCollectionTitle)”。",
                systemImage: nil,
                retryTitle: nil,
                onRetry: nil
            )
        case .failed(_, let error):
            LibraryStatusView(
                title: "无法载入此文件夹",
                message: error.summary,
                systemImage: "exclamationmark.triangle",
                retryTitle: "重试",
                onRetry: onRetryItems
            )
        case .empty:
            LibraryEmptyStateView(collection: selectedCollection) {
                openImportForSelectedFolder()
            }
        case .loaded:
            List(selection: $selectedItemID) {
                ForEach(items) { item in
                    LibraryItemRowView(
                        item: item,
                        isSelected: selectedItemID == item.id,
                        isCurrentItem: currentItemID == item.id,
                        isPlaying: currentItemID == item.id && isPlaying,
                        downloadSession: downloadSession,
                        playbackTimeline: playbackTimeline,
                        onTogglePlayback: { onItemAction(item, .togglePlayback) },
                        onItemAction: { action in
                            onItemAction(item, action)
                        }
                    )
                    .tag(item.id)
                    .draggable(item.id.uuidString)
                    .contextMenu {
                        itemContextMenu(for: item)
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(
                        selectedItemID == item.id ? palette.selection : palette.background
                    )
                    .listRowSeparatorTint(palette.border)
                    .accessibilityIdentifier("library.item.\(item.id.uuidString)")
                }

                if canLoadMoreItems {
                    HStack(spacing: DesignMetrics.space8) {
                        Spacer(minLength: 0)
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityHidden(true)
                        Text("正在载入更多音频…")
                            .font(DesignTypography.metadata)
                            .foregroundStyle(palette.textSecondary)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, DesignMetrics.space12)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(palette.background)
                    .onAppear(perform: onLoadMoreItems)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("library.load-more")
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(palette.background)
            .onKeyPress(.space) {
                guard let selectedItem = selectedItem() else { return .ignored }
                onItemAction(selectedItem, .togglePlayback)
                return .handled
            }
            .onKeyPress(.delete) {
                guard let selectedItem = selectedItem() else { return .ignored }
                onItemAction(selectedItem, .delete)
                return .handled
            }
        }
    }

    @ViewBuilder
    private func itemContextMenu(for item: LibraryItemRow) -> some View {
        Button("现在播放") { onItemAction(item, .playNow) }
        Button("下一项播放") { onItemAction(item, .enqueueNext) }
        Button("添加到队尾") { onItemAction(item, .enqueueLast) }

        Button("移动到…") { onItemAction(item, .move) }

        Divider()
        moreItemMenu(for: item)
    }

    @ViewBuilder
    private func moreItemMenu(for item: LibraryItemRow) -> some View {
        switch item.storageState {
        case .online:
            Button("下载并保存") {
                onItemAction(item, .download)
            }
        case .downloadFailed:
            Button("重试下载") {
                onItemAction(item, .retryDownload)
            }
        case .downloaded:
            EmptyView()
        case .downloading:
            Button("取消下载") {
                onItemAction(item, .cancelDownload)
            }
        }
        if item.storageState != .downloading {
            Divider()
            Button("删除", role: .destructive) {
                onItemAction(item, .delete)
            }
        }
    }

    private func selectedItem() -> LibraryItemRow? {
        guard let selectedItemID else { return nil }
        return items.first(where: { $0.id == selectedItemID })
    }

    private func openImportForSelectedFolder() {
        destination = .importLink(
            ImportEntryContext(destinationFolderID: selectedFolderID)
        )
    }

    private func toggleSettings() {
        isSettingsButtonFocused = false
        onToggleSettings()
    }

    private func closeSettings() {
        onCloseSettings()
        Task { @MainActor in
            await Task.yield()
            isSettingsButtonFocused = true
        }
    }

    private func restoreCollectionPickerFocus() {
        Task { @MainActor in
            await Task.yield()
            isCollectionPickerButtonFocused = true
        }
    }
}

private struct LibraryStatusView: View {
    let title: String
    let message: String
    let systemImage: String?
    let retryTitle: String?
    let onRetry: (() -> Void)?

    @Environment(\.designPalette) private var palette

    var body: some View {
        VStack(spacing: 0) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(DesignTypography.metric)
                    .foregroundStyle(palette.negative)
                    .accessibilityHidden(true)
            } else {
                ProgressView()
                    .controlSize(.small)
                    .tint(palette.accent)
                    .accessibilityHidden(true)
            }

            Text(title)
                .font(DesignTypography.sectionTitle)
                .foregroundStyle(palette.textPrimary)
                .padding(.top, DesignMetrics.space16)

            Text(message)
                .font(DesignTypography.body)
                .foregroundStyle(palette.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 360)
                .padding(.top, DesignMetrics.space8)

            if let retryTitle, let onRetry {
                Button(retryTitle, action: onRetry)
                    .buttonStyle(.bordered)
                    .font(DesignTypography.bodyMedium)
                    .padding(.top, DesignMetrics.space16)
            }
        }
        .padding(DesignMetrics.space24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
    }
}

private struct LibraryEmptyStateView: View {
    let collection: LibraryCollection
    let onImport: () -> Void

    @Environment(\.designPalette) private var palette

    private var copy: (title: String, message: String, action: String) {
        switch collection {
        case .recentlyImported:
            ("这里还没有导入内容", "从链接导入一段声音，它会出现在最近导入中。", "从链接导入")
        case .recentlyPlayed:
            ("还没有播放记录", "播放一条资料库中的音频后，它会显示在这里。", "从链接导入")
        case .downloaded:
            ("还没有已下载音频", "下载一条音频后，即使离线也能在这里找到它。", "从链接导入")
        case .folder:
            ("这里还没有音频", "从链接导入一段声音，再回到这里播放或归档。", "从链接导入")
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: "waveform")
                .font(DesignTypography.metric)
                .foregroundStyle(palette.textSecondary)
                .accessibilityHidden(true)

            Text(copy.title)
                .font(DesignTypography.sectionTitle)
                .foregroundStyle(palette.textPrimary)
                .padding(.top, DesignMetrics.space16)
                .accessibilityIdentifier("library.empty.title")

            Text(copy.message)
                .font(DesignTypography.body)
                .foregroundStyle(palette.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 360)
                .padding(.top, DesignMetrics.space8)

            Button(copy.action, systemImage: "link.badge.plus", action: onImport)
                .buttonStyle(.borderedProminent)
                .font(DesignTypography.bodyMedium)
                .tint(palette.accent)
                .controlSize(.regular)
                .padding(.top, DesignMetrics.space24)
                .accessibilityIdentifier("library.empty.import")
        }
        .padding(DesignMetrics.space24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
    }
}
