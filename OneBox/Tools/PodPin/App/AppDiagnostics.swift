import Foundation
import OSLog

/// Stable, user-supportable failure classifications. Keep raw transport and
/// parser details out of the presentation layer and out of persistent logs.
enum PodPinErrorCode: String, Codable, CaseIterable, Sendable {
    case database
    case network
    case sourceParsing
    case externalTool
    case browserAuthorization
    case fileSystem
    case artwork
    case playback
    case validation
    case unknown
}

struct PresentedError: Error, Equatable, Identifiable, Sendable {
    let id: UUID
    let code: PodPinErrorCode
    let summary: String
    let recoverySuggestion: String
    let technicalReason: String

    var errorID: String { id.uuidString.uppercased() }

    static func message(
        _ summary: String,
        code: PodPinErrorCode = .validation,
        recoverySuggestion: String = "请检查后重试。"
    ) -> PresentedError {
        PresentedError(
            id: UUID(), code: code, summary: summary, recoverySuggestion: recoverySuggestion,
            technicalReason: summary)
    }

    static func from(_ error: Error) -> PresentedError {
        if let presented = error as? PresentedError { return presented }

        let description = AppDiagnostics.redact(error.localizedDescription)
        let code: PodPinErrorCode
        let summary: String
        let recovery: String

        if error is CancellationError {
            code = .unknown
            summary = "操作已取消"
            recovery = "可以在准备好后重新开始。"
        } else if let importError = error as? ContentImportError {
            switch importError {
            case .unsupportedURL, .unsupportedContent, .restrictedContent, .malformedToolOutput,
                .malformedResponse, .contentChanged, .platformUnavailable:
                code = .sourceParsing
                summary = "无法识别这个音频链接"
                recovery = "确认链接公开可访问后重试。"
            case .browserAccessRequired, .browserAccessFailed:
                code = .browserAuthorization
                summary = "需要确认浏览器访客状态"
                recovery = "在导入页选择一个浏览器 Profile 后重试。"
            case .toolUnavailable, .externalToolFailed:
                code = .externalTool
                summary = "暂时无法准备音频"
                recovery = "请稍后重试；若持续失败，请复制错误信息排查。"
            case .mediaUnavailable, .invalidDownloadedAudio:
                code = .playback
                summary = "音频暂时无法播放"
                recovery = "请稍后重试，或重新下载到本机。"
            case .cancelled:
                code = .unknown
                summary = "操作已取消"
                recovery = "可以在准备好后重新开始。"
            }
        } else if let databaseError = error as? MarketDatabaseError {
            switch databaseError {
            case .emptyFolderName, .duplicateFolderName, .cannotDeleteNonEmptyFolder,
                .cannotMoveFolderIntoItself, .cannotMoveFolderIntoDescendant,
                .invalidContentID, .invalidTitle, .invalidSourceURL, .invalidDuration,
                .invalidRelativePath, .invalidDownloadState:
                code = .validation
                summary = "这个操作当前不可用"
                recovery = "检查名称、目标位置或内容状态后重试。"
            default:
                code = .database
                summary = "资料库更新没有完成"
                recovery = "请重试；若问题持续，请复制错误信息。"
            }
        } else if error is URLError {
            code = .network
            summary = "网络请求没有完成"
            recovery = "检查网络连接后重试。"
        } else if error is CocoaError {
            code = .fileSystem
            summary = "本地文件操作没有完成"
            recovery = "检查磁盘空间和应用文件权限后重试。"
        } else {
            code = .unknown
            summary = "操作没有完成"
            recovery = "请重试；若问题持续，请复制错误信息。"
        }

        return PresentedError(
            id: UUID(),
            code: code,
            summary: summary,
            recoverySuggestion: recovery,
            technicalReason: description
        )
    }
}

struct DiagnosticEvent: Sendable {
    enum Level: String, Sendable { case debug, info, warning, error }

    let level: Level
    let category: String
    let event: String
    let operationID: UUID?
    let errorID: UUID?
    let errorCode: PodPinErrorCode?
}

/// A narrow diagnostics seam backed only by macOS Unified Logging. Callers
/// submit operation facts; raw errors, user content, context, and source paths
/// are never written to the log.
actor AppDiagnostics {
    static let shared = AppDiagnostics()

    private static let subsystem = "com.cmy.OneBox.podpin"
    private static let allowedCategories: Set<String> = [
        "app", "database", "library", "playback", "storage",
    ]
    private static let allowedEvents: Set<String> = [
        "download.failed-media.cleanup.failed",
        "download.failure-state.persist.failed",
        "download.stale-media.cleanup.failed",
        "folder.create.finished",
        "folder.create.started",
        "folder.delete.check.failed",
        "interrupted-download.cleanup.failed",
        "item.delete-media.cleanup.failed",
        "operation.failed",
        "page.load-more.failed",
        "queue.consume-after-ready.failed",
        "recovery.lookup.failed",
        "recovery.position.persist.failed",
        "refresh.failed",
        "shutdown.position.flush.failed",
    ]

    func record(
        level: DiagnosticEvent.Level = .info,
        category: String,
        event: String,
        operationID: UUID? = nil,
        error: PresentedError? = nil
    ) {
        let diagnostic = DiagnosticEvent(
            level: level,
            category: Self.allowedIdentifier(
                category, allowedValues: Self.allowedCategories, fallback: "diagnostics"),
            event: Self.allowedIdentifier(
                event, allowedValues: Self.allowedEvents, fallback: "event"),
            operationID: operationID,
            errorID: error?.id,
            errorCode: error?.code
        )
        writeToUnifiedLog(diagnostic)
    }

    private func writeToUnifiedLog(_ diagnostic: DiagnosticEvent) {
        let logger = Logger(subsystem: Self.subsystem, category: diagnostic.category)
        let message =
            "\(diagnostic.event) operation=\(diagnostic.operationID?.uuidString ?? "") error=\(diagnostic.errorCode?.rawValue ?? "") errorID=\(diagnostic.errorID?.uuidString ?? "")"
        switch diagnostic.level {
        case .debug: logger.debug("\(message, privacy: .public)")
        case .info: logger.info("\(message, privacy: .public)")
        case .warning: logger.warning("\(message, privacy: .public)")
        case .error: logger.error("\(message, privacy: .public)")
        }
    }

    private static func allowedIdentifier(
        _ value: String,
        allowedValues: Set<String>,
        fallback: String
    ) -> String {
        allowedValues.contains(value) ? value : fallback
    }

    static func redact(_ value: String) -> String {
        value
            .replacingOccurrences(
                of: "(?i)\\b[A-Za-z][A-Za-z0-9+.-]*://[^\\s]+",
                with: "[redacted-url]",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: "(?i)(?<![A-Za-z0-9_])(?:bearer|basic)\\s+[^\\s,;]+",
                with: "[redacted-authorization]",
                options: .regularExpression
            )
            .replacingOccurrences(
                of:
                    "(?i)(?<![A-Za-z0-9_])[\"']?(?:(?:access|api|client|encryption|private)[_-]?(?:key|secret|token)|authorization|cookie|key|login|password|secret|session|token|user[_-]?name|user)[\"']?(?![A-Za-z0-9_])\\s*[:=]\\s*(?:\"[^\"]*\"|'[^']*'|[^\\s,;]+)",
                with: "[redacted-sensitive-value]",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: "(?<![A-Za-z0-9:])/(?!/)[^\\n,;]+",
                with: "[redacted-path]",
                options: .regularExpression
            )
    }
}
