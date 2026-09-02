import AppKit
import OneBoxDesignSystem
import SwiftUI

/// The import workspace deliberately keeps the raw share text visible. It
/// accepts one source link at a time; that link may discover an ordered
/// Bilibili multi-part selection handled by the same import model.
struct ImportWorkspaceView: View {
    @ObservedObject var store: PodPinStore
    @ObservedObject private var importSession: ImportSession
    let entryContext: ImportEntryContext
    let onImportSucceeded: @MainActor @Sendable (UUID?) -> Void
    let onRequestFolderEditor: @MainActor @Sendable (FolderEditorRequest) -> Void
    @EnvironmentObject private var navigator: AppNavigator
    @Environment(\.designPalette) private var palette

    @State private var shareText = ""
    @State private var preview: ImportDiscovery?
    @State private var selectedContentIDs = Set<String>()
    @State private var destinationFolderID: UUID
    @State private var isProbing = false
    @State private var isImporting = false
    @State private var isVisible = false
    @State private var probeTask: Task<Void, Never>?
    @State private var selectedBrowserProfileID: String?
    @State private var probeGeneration = 0

    init(
        store: PodPinStore,
        entryContext: ImportEntryContext,
        onImportSucceeded: @escaping @MainActor @Sendable (UUID?) -> Void,
        onRequestFolderEditor: @escaping @MainActor @Sendable (FolderEditorRequest) -> Void
    ) {
        self.store = store
        self.importSession = store.importSession
        self.entryContext = entryContext
        self.onImportSucceeded = onImportSucceeded
        self.onRequestFolderEditor = onRequestFolderEditor
        _destinationFolderID = State(initialValue: entryContext.destinationFolderID)
    }

    private var candidates: ImportLinkCandidates {
        ImportLinkParser.candidates(in: shareText)
    }

    var body: some View {
        importWorkspace
            .sheet(isPresented: verificationPresented) {
                if let request = importSession.verificationRequest {
                    verificationWorkspace(request)
                }
            }
            .onAppear {
                isVisible = true
                store.dismissImportIssue()
            }
            .onDisappear {
                isVisible = false
                probeTask?.cancel()
                if importSession.verificationRequest != nil {
                    store.cancelVerification()
                }
                store.discardPendingBrowserAccess()
            }
            .onChange(of: importSession.browserProfiles) { _, profiles in
                if !profiles.contains(where: { $0.id == selectedBrowserProfileID }) {
                    selectedBrowserProfileID = profiles.first?.id
                }
            }
    }

    private var importWorkspace: some View {
        WorkspacePage {
            VStack(alignment: .leading, spacing: DesignMetrics.space16) {
                VStack(alignment: .leading, spacing: DesignMetrics.space8) {
                    HStack {
                        Text("分享内容或公开链接")
                            .font(DesignTypography.sectionTitle)
                            .foregroundStyle(palette.textPrimary)

                        Spacer(minLength: DesignMetrics.space8)

                        Button("粘贴") {
                            pasteFromClipboard()
                        }
                        .disabled(isImporting)
                        .accessibilityIdentifier("import.paste")
                    }

                    Text("支持 B 站、抖音、小宇宙和 Fireside；一次粘贴一条公开链接。")
                        .font(DesignTypography.metadata)
                        .foregroundStyle(palette.textSecondary)

                    ZStack(alignment: .topLeading) {
                        TextEditor(text: $shareText)
                            .font(DesignTypography.body)
                            .foregroundStyle(palette.textPrimary)
                            .scrollContentBackground(.hidden)
                            .padding(DesignMetrics.space8)
                            .frame(minHeight: 88)
                            .disabled(isImporting)
                            .onChange(of: shareText) { _, _ in
                                resetForLinkChange()
                            }

                        if shareText.isEmpty {
                            Text("粘贴公开链接")
                                .font(DesignTypography.body)
                                .foregroundStyle(palette.textSecondary)
                                .padding(DesignMetrics.space16)
                                .allowsHitTesting(false)
                        }
                    }
                    .background(palette.surface)
                    .clipShape(.rect(cornerRadius: DesignMetrics.cornerRadius))
                    .overlay {
                        RoundedRectangle(cornerRadius: DesignMetrics.cornerRadius)
                            .strokeBorder(palette.border, lineWidth: 1)
                    }
                }

                if let preview {
                    if preview.isCollection {
                        collectionPreview(preview)
                    } else {
                        itemPreview(preview.primaryItem)
                    }
                }

                importFeedback
                actionBar
            }
        }
    }

    @ViewBuilder
    private var candidateSummary: some View {
        if candidates.urls.isEmpty,
            !shareText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            Label(
                candidates.detectedHTTPSURLCount == 0
                    ? "还没有识别到 HTTPS 公开链接。"
                    : "没有找到支持的公开链接。",
                systemImage: "exclamationmark.circle"
            )
            .font(DesignTypography.metadata)
            .foregroundStyle(palette.textSecondary)
        } else if candidates.urls.count == 1, let url = candidates.urls.first {
            HStack(spacing: DesignMetrics.space8) {
                Image(
                    systemName: isProbing
                        ? "arrow.triangle.2.circlepath"
                        : "checkmark.circle.fill"
                )
                .foregroundStyle(isProbing ? palette.accent : palette.positive)

                Text(url.host ?? url.absoluteString)
                    .font(DesignTypography.metadata.monospaced())
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)

                Spacer(minLength: DesignMetrics.space8)

                Text(isProbing ? "正在解析" : "已识别")
                    .font(DesignTypography.bodyMedium)
                    .foregroundStyle(palette.textSecondary)
            }
        } else if candidates.urls.count > 1 {
            Label(
                "检测到 \(candidates.urls.count) 条链接，请只保留一条。",
                systemImage: "rectangle.stack.badge.exclamationmark"
            )
            .font(DesignTypography.bodyMedium)
            .foregroundStyle(palette.negative)
        }
    }

    @ViewBuilder
    private var importFeedback: some View {
        if let error = importSession.issue {
            inlineIssue(error)
        } else if isProbing || isImporting || store.activityMessage != nil {
            VStack(alignment: .leading, spacing: DesignMetrics.space8) {
                HStack(spacing: DesignMetrics.space8) {
                    ProgressView().controlSize(.small)
                    Text(
                        store.activityMessage
                            ?? (isImporting ? "正在添加到资料库…" : "正在解析链接…")
                    )
                }
                if isImporting {
                    DownloadProgressView(session: store.downloadSession, itemID: nil)
                        .frame(maxWidth: 360)
                }
            }
            .font(DesignTypography.body)
            .foregroundStyle(palette.textSecondary)
            .accessibilityIdentifier("import.feedback.progress")
        } else {
            candidateSummary
        }
    }

    private func itemPreview(_ metadata: ImportedAudioMetadata) -> some View {
        VStack(alignment: .leading, spacing: DesignMetrics.space12) {
            Text("识别结果")
                .font(DesignTypography.sectionTitle)
                .foregroundStyle(palette.textPrimary)

            HStack(spacing: DesignMetrics.space12) {
                Image(systemName: "waveform")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(palette.textSecondary)
                    .frame(
                        width: DesignMetrics.titlebarControlSize,
                        height: DesignMetrics.titlebarControlSize
                    )
                    .background(palette.surfaceElevated)
                    .clipShape(.rect(cornerRadius: DesignMetrics.cornerRadius))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: DesignMetrics.space4) {
                    Text(metadata.title)
                        .font(DesignTypography.bodyMedium)
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(2)
                    Text(
                        metadata.author.flatMap { $0.isEmpty ? nil : $0 }
                            ?? sourceLabel(for: metadata.platform)
                    )
                    .font(DesignTypography.metadata)
                    .foregroundStyle(palette.textSecondary)
                }

                Spacer(minLength: DesignMetrics.space8)

                if let duration = metadata.duration, duration > 0 {
                    Text(PlaybackTimeFormatter.string(for: duration))
                        .font(DesignTypography.metadata.monospacedDigit())
                        .foregroundStyle(palette.textSecondary)
                }
            }

            destinationPicker
        }
        .padding(.vertical, DesignMetrics.space8)
    }

    private func collectionPreview(_ discovery: ImportDiscovery) -> some View {
        VStack(alignment: .leading, spacing: DesignMetrics.space12) {
            HStack {
                VStack(alignment: .leading, spacing: DesignMetrics.space4) {
                    Text(discovery.groupTitle ?? discovery.primaryItem.title)
                        .font(DesignTypography.sectionTitle)
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(2)
                    Text("已选择 \(selectedContentIDs.count) / \(discovery.items.count) 项")
                        .font(DesignTypography.metadata)
                        .foregroundStyle(palette.textSecondary)
                }

                Spacer(minLength: DesignMetrics.space8)

                Button(selectedContentIDs.count == discovery.items.count ? "取消全选" : "全选") {
                    if selectedContentIDs.count == discovery.items.count {
                        selectedContentIDs = []
                    } else {
                        selectedContentIDs = Set(discovery.items.map(\.contentID))
                    }
                }
            }

            Divider()

            LazyVStack(spacing: 0) {
                ForEach(Array(discovery.items.enumerated()), id: \.element.id) { index, item in
                    Button {
                        if selectedContentIDs.contains(item.contentID) {
                            selectedContentIDs.remove(item.contentID)
                        } else {
                            selectedContentIDs.insert(item.contentID)
                        }
                    } label: {
                        HStack(spacing: DesignMetrics.space8) {
                            Image(
                                systemName: selectedContentIDs.contains(item.contentID)
                                    ? "checkmark.square.fill"
                                    : "square"
                            )
                            .foregroundStyle(
                                selectedContentIDs.contains(item.contentID)
                                    ? palette.accent
                                    : palette.textSecondary
                            )

                            Text("P\(index + 1)")
                                .font(DesignTypography.metadata.monospacedDigit())
                                .foregroundStyle(palette.textSecondary)
                                .frame(
                                    width: DesignMetrics.titlebarControlSize, alignment: .leading)

                            Text(item.title)
                                .font(DesignTypography.body)
                                .foregroundStyle(palette.textPrimary)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            if let duration = item.duration, duration > 0 {
                                Text(PlaybackTimeFormatter.string(for: duration))
                                    .font(DesignTypography.metadata.monospacedDigit())
                                    .foregroundStyle(palette.textSecondary)
                            }
                        }
                        .contentShape(.rect)
                        .padding(.vertical, DesignMetrics.space8)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        selectedContentIDs.contains(item.contentID)
                            ? "取消选择 \(item.title)"
                            : "选择 \(item.title)"
                    )

                    if index < discovery.items.count - 1 {
                        Divider()
                    }
                }
            }

            destinationPicker
        }
        .padding(.vertical, DesignMetrics.space8)
    }

    private var actionBar: some View {
        HStack(spacing: DesignMetrics.space8) {
            if preview != nil {
                Button("重新粘贴") {
                    shareText = ""
                    preview = nil
                    selectedContentIDs = []
                    store.dismissImportIssue()
                }
            }

            Spacer(minLength: DesignMetrics.space8)

            if preview == nil, importSession.issue != nil {
                Button("重试") { beginProbe() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!candidates.hasExactlyOneSupportedURL || isProbing)
                    .accessibilityIdentifier("import.retry")
            } else {
                Button(primaryImportTitle) {
                    beginImport(as: .stream)
                }
                .disabled(isImporting || selectedContentIDs.isEmpty)
                .accessibilityIdentifier("import.add-and-play")

                Button("下载到本机") {
                    beginImport(as: .download)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isImporting || selectedContentIDs.isEmpty)
                .accessibilityIdentifier("import.download-and-save")
            }
        }
        .font(DesignTypography.body)
    }

    private func inlineIssue(_ error: PresentedError) -> some View {
        HStack(alignment: .top, spacing: DesignMetrics.space8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: DesignMetrics.space4) {
                Text(error.summary)
                    .font(DesignTypography.bodyMedium)
                Text("错误 ID：\(error.errorID)")
                    .font(DesignTypography.metadata.monospaced())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(palette.negative)
        .padding(DesignMetrics.space12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.surfaceElevated)
        .clipShape(.rect(cornerRadius: DesignMetrics.cornerRadius))
        .accessibilityElement(children: .combine)
    }

    private func verificationWorkspace(_ request: PlatformVerificationRequest) -> some View {
        VStack(alignment: .leading, spacing: DesignMetrics.space16) {
            VStack(alignment: .leading, spacing: DesignMetrics.space4) {
                Text("借用 \(request.platformName) 的访客状态")
                    .font(DesignTypography.sectionTitle)
                    .foregroundStyle(palette.textPrimary)
                Text("只读访问所选 Chrome、Edge 或 Chromium Profile，并排除登录、UID、会员和支付 Cookie。")
                    .font(DesignTypography.body)
                    .foregroundStyle(palette.textSecondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: DesignMetrics.space12) {
                if !importSession.hasRequestedBrowserProfiles {
                    Button("查找浏览器 Profile") {
                        store.discoverBrowserProfiles()
                    }
                    .buttonStyle(.bordered)
                    .help("明确允许 PodPin 读取本机浏览器 Profile 名称")
                } else if importSession.isDiscoveringBrowserProfiles {
                    HStack(spacing: DesignMetrics.space8) {
                        ProgressView().controlSize(.small)
                        Text("正在查找可用 Profile…")
                    }
                    .foregroundStyle(palette.textSecondary)
                } else if importSession.browserProfiles.isEmpty {
                    VStack(alignment: .leading, spacing: DesignMetrics.space8) {
                        Label(
                            "没有找到可用的 Chrome、Edge 或 Chromium Profile。",
                            systemImage: "person.crop.circle.badge.exclamationmark"
                        )
                        .foregroundStyle(palette.textSecondary)
                        Button("重新查找") {
                            store.discoverBrowserProfiles()
                        }
                        .buttonStyle(.bordered)
                    }
                } else {
                    Picker("浏览器 Profile", selection: $selectedBrowserProfileID) {
                        ForEach(importSession.browserProfiles) { profile in
                            Text("\(profile.browserName) — \(profile.displayName)")
                                .tag(Optional(profile.id))
                        }
                    }
                    .pickerStyle(.radioGroup)
                }

                Text("系统可能显示钥匙串授权提示。Cookie 和临时媒体信息只存在内存中，不写入数据库或日志。")
                    .font(DesignTypography.metadata)
                    .foregroundStyle(palette.textSecondary)
            }

            Spacer(minLength: 0)

            HStack {
                Button("取消") {
                    store.cancelVerification()
                }

                Spacer(minLength: DesignMetrics.space8)

                Button("使用所选 Profile 重试") {
                    retryAfterBrowserAccess()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isProbing || selectedBrowserProfileID == nil)
            }
        }
        .font(DesignTypography.body)
        .padding(DesignMetrics.space24)
        .frame(width: 520, height: 320, alignment: .topLeading)
        .background(palette.background)
    }

    private var destinationPicker: some View {
        Menu {
            FolderDestinationMenu(
                folders: store.folderTree(),
                selectedFolderID: destinationFolderID,
                systemFolderLabel: "收件箱"
            ) { folder in
                destinationFolderID = folder.id
            }
            Divider()
            Button("新建文件夹…") {
                onRequestFolderEditor(
                    FolderEditorRequest(
                        operation: .create,
                        source: .importWorkspace,
                        defaultParentID: destinationFolderID == LibraryFolder.inboxID
                            ? entryContext.defaultNewFolderParentID
                            : destinationFolderID,
                        onSaved: { folder in
                            destinationFolderID = folder.id
                        }
                    )
                )
            }
        } label: {
            HStack(spacing: DesignMetrics.space4) {
                Text("归档到")
                    .foregroundStyle(palette.textSecondary)
                Text(destinationFolderLabel)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(palette.textSecondary)
                    .accessibilityHidden(true)
            }
            .font(DesignTypography.body)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .accessibilityLabel("归档到 \(destinationFolderLabel)")
        .accessibilityValue(destinationFolderLabel)
        .accessibilityIdentifier("import.destination")
    }

    private var destinationFolderLabel: String {
        store.folders.first(where: { $0.id == destinationFolderID })?.displayName ?? "收件箱"
    }

    private func resetForLinkChange() {
        probeTask?.cancel()
        probeGeneration &+= 1
        preview = nil
        selectedContentIDs = []
        isProbing = false
        store.dismissImportIssue()
        store.discardPendingBrowserAccess()

        guard candidates.hasExactlyOneSupportedURL else { return }
        let expectedText = shareText
        let generation = probeGeneration
        probeTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: 300_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled,
                generation == probeGeneration,
                shareText == expectedText,
                candidates.hasExactlyOneSupportedURL
            else { return }
            await probe(text: expectedText, generation: generation)
        }
    }

    private func pasteFromClipboard() {
        guard let pastedText = NSPasteboard.general.string(forType: .string) else { return }
        shareText = pastedText
    }

    private func beginProbe() {
        guard candidates.hasExactlyOneSupportedURL else { return }
        probeTask?.cancel()
        probeGeneration &+= 1
        let generation = probeGeneration
        let expectedText = shareText
        probeTask = Task { @MainActor in
            await probe(text: expectedText, generation: generation)
        }
    }

    private func probe(text: String, generation: Int) async {
        guard generation == probeGeneration, !Task.isCancelled else { return }
        isProbing = true
        defer {
            if generation == probeGeneration {
                isProbing = false
            }
        }
        let discovery = await store.probe(urlText: text)
        guard !Task.isCancelled,
            generation == probeGeneration,
            shareText == text
        else { return }
        preview = discovery
        selectedContentIDs = Set(discovery?.items.map(\.contentID) ?? [])
    }

    private func retryAfterBrowserAccess() {
        guard
            let profile = importSession.browserProfiles.first(where: {
                $0.id == selectedBrowserProfileID
            })
        else {
            return
        }
        probeTask?.cancel()
        probeGeneration &+= 1
        let generation = probeGeneration
        probeTask = Task { @MainActor in
            isProbing = true
            defer {
                if generation == probeGeneration {
                    isProbing = false
                }
            }
            let discovery = await store.retryBrowserAccess(using: profile)
            guard !Task.isCancelled, generation == probeGeneration else { return }
            if let discovery {
                preview = discovery
                selectedContentIDs = Set(discovery.items.map(\.contentID))
            } else if importSession.verificationRequest == nil, store.userFacingError == nil {
                navigator.showLibraryContent()
            }
        }
    }

    private func beginImport(as choice: PodPinStore.ImportChoice) {
        guard let preview else { return }
        isImporting = true
        store.startImportDiscovery(
            preview,
            selectedContentIDs: selectedContentIDs,
            into: destinationFolderID,
            choice: choice
        ) { savedItems in
            isImporting = false
            if let savedItems {
                onImportSucceeded(savedItems.first?.id)
                if isVisible {
                    navigator.showLibraryContent()
                }
            }
        }
    }

    private func sourceLabel(for platform: AudioPlatform) -> String {
        switch platform {
        case .fixture: "PodPin 示例"
        case .bilibili: "B 站"
        case .douyin: "抖音"
        case .fireside: "Fireside"
        case .xiaoyuzhou: "小宇宙"
        }
    }

    private var verificationPresented: Binding<Bool> {
        Binding(
            get: { importSession.verificationRequest != nil },
            set: { visible in
                if !visible { store.cancelVerification() }
            })
    }

    private var primaryImportTitle: String {
        guard let preview, preview.isCollection else { return "添加并播放" }
        return selectedContentIDs.count == 1 ? "添加并播放" : "添加 \(selectedContentIDs.count) 项"
    }

}
