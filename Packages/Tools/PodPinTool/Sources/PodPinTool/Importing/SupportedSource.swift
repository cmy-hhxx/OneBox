import Foundation

enum SupportedSource: String, CaseIterable, Sendable {
    case bilibili
    case douyin
    case fireside
    case xiaoyuzhou

    static func source(for url: URL) -> SupportedSource? {
        guard url.scheme?.lowercased() == "https",
            let host = url.host?.lowercased()
        else { return nil }

        if host == "b23.tv" || host == "www.b23.tv" || host.hasSuffix(".bilibili.com") {
            return .bilibili
        }
        if host == "v.douyin.com" || host == "www.douyin.com" || host == "douyin.com"
            || host.hasSuffix(".douyin.com") || host.hasSuffix(".iesdouyin.com")
        {
            return .douyin
        }
        if host == "www.xiaoyuzhoufm.com" || host == "xiaoyuzhoufm.com" {
            return .xiaoyuzhou
        }
        if host.hasSuffix(".fireside.fm") {
            return .fireside
        }
        return nil
    }

    /// Source websites expose far more URL kinds than PodPin deliberately
    /// accepts. Require a concrete public content path before routing.
    static func validateSinglePublicItem(url: URL) throws -> SupportedSource {
        guard let source = source(for: url) else {
            throw ContentImportError.unsupportedURL
        }

        let host = url.host?.lowercased() ?? ""
        let pathComponents = url.path.split(separator: "/", omittingEmptySubsequences: true)
        let firstPathComponent = pathComponents.first?.lowercased()

        switch source {
        case .bilibili:
            let isContentPath =
                host.hasSuffix(".bilibili.com")
                && pathComponents.count >= 2
                && firstPathComponent == "video"
                && !pathComponents[1].isEmpty
            let isShortLink =
                (host == "b23.tv" || host == "www.b23.tv")
                && pathComponents.count == 1
                && !pathComponents[0].isEmpty
            guard isContentPath || isShortLink else {
                throw ContentImportError.unsupportedContent("请粘贴一条 B 站公开视频链接，不支持主页、合集或直播。")
            }
        case .douyin:
            let isContentPath =
                host != "v.douyin.com"
                && pathComponents.count >= 2
                && firstPathComponent == "video"
                && !pathComponents[1].isEmpty
            let isShortLink =
                host == "v.douyin.com"
                && pathComponents.count == 1
                && !pathComponents[0].isEmpty
            guard isContentPath || isShortLink else {
                throw ContentImportError.unsupportedContent("请粘贴一条抖音公开视频链接，不支持主页、合集或直播。")
            }
        case .xiaoyuzhou:
            let episodeID = pathComponents.count == 2 ? String(pathComponents[1]) : ""
            let isEpisode =
                firstPathComponent == "episode"
                && episodeID.count == 24
                && episodeID.allSatisfy(\.isHexDigit)
            guard isEpisode else {
                throw ContentImportError.unsupportedContent("请粘贴一条小宇宙公开单集链接。")
            }
        case .fireside:
            let episodeNumber = pathComponents.count == 1 ? String(pathComponents[0]) : ""
            let isEpisode =
                !episodeNumber.isEmpty
                && episodeNumber.allSatisfy(\.isNumber)
            guard isEpisode else {
                throw ContentImportError.unsupportedContent("请粘贴一条 Fireside 公开单集链接。")
            }
        }

        return source
    }

    /// The anonymous verifier may follow only first-party HTTPS navigations.
    /// This includes normal short-link redirects, but prevents the embedded
    /// challenge view from becoming a general-purpose browser.
    func acceptsVerificationNavigation(to url: URL) -> Bool {
        Self.source(for: url) == self
    }

    var platform: AudioPlatform {
        switch self {
        case .bilibili: .bilibili
        case .douyin: .douyin
        case .fireside: .fireside
        case .xiaoyuzhou: .xiaoyuzhou
        }
    }
}
