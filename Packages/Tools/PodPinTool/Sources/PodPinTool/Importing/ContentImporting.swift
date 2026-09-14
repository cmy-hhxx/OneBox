import Foundation

/// The small boundary between PodPin's library and a source-specific extractor.
///
/// An importer never owns library persistence or playback. It only turns a public
/// source URL into metadata, a short-lived stream URL, or a verified local file.
protocol ContentImporting: Sendable {
    func probe(url: URL, attempt: ImportAttempt) async throws -> ImportDiscovery
    func resolveStream(
        for content: ImportedAudioMetadata,
        attempt: ImportAttempt
    ) async throws -> ResolvedAudioStream
    func download(
        content: ImportedAudioMetadata,
        to destinationDirectory: URL,
        attempt: ImportAttempt,
        progress: @escaping @Sendable (DownloadProgressSnapshot) -> Void
    ) async throws -> DownloadedAudioFile
}

extension ContentImporting {
    func probe(url: URL) async throws -> ImportDiscovery {
        try await probe(url: url, attempt: .anonymous)
    }

    func resolveStream(for content: ImportedAudioMetadata) async throws -> ResolvedAudioStream {
        try await resolveStream(for: content, attempt: .anonymous)
    }

    func download(
        content: ImportedAudioMetadata,
        to destinationDirectory: URL,
        progress: @escaping @Sendable (DownloadProgressSnapshot) -> Void
    ) async throws -> DownloadedAudioFile {
        try await download(
            content: content,
            to: destinationDirectory,
            attempt: .anonymous,
            progress: progress
        )
    }
}

/// A successful probe is structurally non-empty. A single-item source uses
/// only `primaryItem`; ordered source collections append their remaining items.
struct ImportDiscovery: Equatable, Sendable {
    let sourceURL: URL
    let groupTitle: String?
    let primaryItem: ImportedAudioMetadata
    let remainingItems: [ImportedAudioMetadata]

    var items: [ImportedAudioMetadata] { [primaryItem] + remainingItems }
    var isCollection: Bool { !remainingItems.isEmpty }

    init(
        sourceURL: URL,
        groupTitle: String? = nil,
        primaryItem: ImportedAudioMetadata,
        remainingItems: [ImportedAudioMetadata] = []
    ) {
        self.sourceURL = sourceURL
        self.groupTitle = remainingItems.isEmpty ? nil : groupTitle
        self.primaryItem = primaryItem
        self.remainingItems = remainingItems
    }
}

enum ImportAttempt: Sendable {
    case anonymous
    case browserRetry(BrowserAccessLease)
}

/// An in-memory, operation-scoped grant. It is deliberately neither Codable
/// nor printable, so browser state cannot enter persistence or diagnostics.
struct BrowserAccessLease: @unchecked Sendable {
    let id: UUID
    let source: SupportedSource
    let sourceURL: URL
    let contentIDs: Set<String>
    let expiresAt: Date
    let cookies: [HTTPCookie]
    private let state: BrowserAccessLeaseState

    init(
        source: SupportedSource,
        sourceURL: URL,
        contentIDs: Set<String>,
        expiresAt: Date,
        cookies: [HTTPCookie]
    ) {
        id = UUID()
        self.source = source
        self.sourceURL = sourceURL
        self.contentIDs = contentIDs
        self.expiresAt = expiresAt
        self.cookies = cookies
        state = BrowserAccessLeaseState()
    }

    func consume(source: SupportedSource, url: URL, contentID: String?) -> Bool {
        guard self.source == source,
            expiresAt > Date(),
            sourceURL == url,
            contentID.map(contentIDs.contains) ?? contentIDs.isEmpty
        else { return false }
        return state.consume(contentID: contentID)
    }

    func revoke() {
        state.revoke()
    }

    func scoped(to sourceURL: URL, contentIDs: Set<String>) -> BrowserAccessLease {
        BrowserAccessLease(
            source: source,
            sourceURL: sourceURL,
            contentIDs: contentIDs,
            expiresAt: expiresAt,
            cookies: cookies
        )
    }
}

private final class BrowserAccessLeaseState: @unchecked Sendable {
    private let lock = NSLock()
    private var isRevoked = false
    private var consumedOperations = Set<String>()

    func consume(contentID: String?) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let operation = contentID ?? "<probe>"
        guard !isRevoked, consumedOperations.insert(operation).inserted else { return false }
        return true
    }

    func revoke() {
        lock.lock()
        isRevoked = true
        lock.unlock()
    }
}

struct ImportedAudioMetadata: Equatable, Sendable, Identifiable {
    let platform: AudioPlatform
    let contentID: String
    let sourceURL: URL
    let title: String
    let author: String?
    let artworkURL: URL?
    let duration: TimeInterval?

    var id: String { "\(platform.rawValue):\(contentID)" }
}

struct ResolvedAudioStream: Equatable, Sendable {
    let url: URL
    let headers: [String: String]
    let duration: TimeInterval?
    let mimeType: String?

    init(
        url: URL,
        headers: [String: String],
        duration: TimeInterval?,
        mimeType: String? = nil
    ) {
        self.url = url
        self.headers = headers
        self.duration = duration
        self.mimeType = mimeType
    }
}

struct DownloadedAudioFile: Equatable, Sendable {
    /// The fully validated file, located below the destination directory.
    let url: URL
    let duration: TimeInterval
}

/// A platform can require a short-lived, anonymous web challenge even for a
/// public item. This request never carries an account, browser profile, or
/// persistent session data.
struct PlatformVerificationRequest: Equatable, Sendable, Identifiable {
    let source: SupportedSource
    let url: URL

    var id: String { "\(source.rawValue):\(url.absoluteString)" }

    var platformName: String {
        switch source {
        case .bilibili: "B 站"
        case .douyin: "抖音"
        case .fireside: "Fireside"
        case .xiaoyuzhou: "小宇宙"
        }
    }
}

enum ContentImportError: LocalizedError, Equatable, Sendable {
    case unsupportedURL
    case unsupportedContent(String)
    case restrictedContent(String)
    case toolUnavailable(String)
    case malformedToolOutput
    case malformedResponse
    case mediaUnavailable(String)
    case contentChanged
    case cancelled
    case invalidDownloadedAudio
    case externalToolFailed(String)
    case browserAccessRequired(PlatformVerificationRequest)
    case browserAccessFailed(String)
    case platformUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedURL:
            return "只支持 B 站、抖音、小宇宙和 Fireside 的公开内容链接。"
        case .unsupportedContent(let reason):
            return reason
        case .restrictedContent(let reason):
            return reason
        case .toolUnavailable(let name):
            return "当前应用缺少内置 \(name)，请安装包含下载组件的完整版本。"
        case .malformedToolOutput:
            return "内容解析结果不完整，无法导入。"
        case .malformedResponse:
            return "来源返回的内容结构已经变化，暂时无法解析。"
        case .mediaUnavailable(let reason):
            return reason
        case .contentChanged:
            return "来源内容的身份已经变化，请重新解析链接。"
        case .cancelled:
            return "导入已取消。"
        case .invalidDownloadedAudio:
            return "下载的文件不包含可播放音频。"
        case .externalToolFailed(let message):
            return message
        case .browserAccessRequired(let request):
            return "\(request.platformName) 需要完成一次临时网页验证后才能解析这条公开内容。"
        case .browserAccessFailed(let message), .platformUnavailable(let message):
            return message
        }
    }
}

/// Retains a raw transport/parser/process failure until the store reports it.
/// UI classification stays independent from the diagnostic error chain.
struct ContentImportFailure: Error, LocalizedError, CustomNSError {
    let underlying: any Error
    let presentation: ContentImportError

    var errorDescription: String? { presentation.localizedDescription }
    static var errorDomain: String { "PodPin.ContentImport" }
    var errorCode: Int { 1 }
    var errorUserInfo: [String: Any] {
        [
            NSLocalizedDescriptionKey: presentation.localizedDescription,
            NSUnderlyingErrorKey: underlying as NSError,
        ]
    }

    static func toolFailure(
        _ result: ExternalToolResult, tool: String, presentation: ContentImportError
    ) -> ContentImportFailure {
        ContentImportFailure(
            underlying: NSError(
                domain: "PodPin.ExternalTool.\(tool)",
                code: Int(result.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: result.standardError]
            ),
            presentation: presentation
        )
    }
}
