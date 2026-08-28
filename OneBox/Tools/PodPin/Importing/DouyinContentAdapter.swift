import Foundation

struct DouyinRenderedPage: @unchecked Sendable {
    let canonicalURL: URL
    let title: String
    let author: String?
    let artworkURL: URL?
    let duration: TimeInterval?
    let audioURL: URL
    let userAgent: String
    let cookies: [HTTPCookie]
}

protocol DouyinRenderedPageLoading: Sendable {
    func load(url: URL, cookies: [HTTPCookie]) async throws -> DouyinRenderedPage
}

enum DouyinPageLoadError: Error, Equatable, Sendable {
    case challenge([String])
    case restricted([String])
    case ambiguousAudio(String)
    case timeout(String)
    case navigation
}

actor DouyinContentAdapter: ContentSourceAdapter {
    let source = SupportedSource.douyin

    private let pageLoader: any DouyinRenderedPageLoading

    init(pageLoader: any DouyinRenderedPageLoading = DouyinWebPageLoader()) {
        self.pageLoader = pageLoader
    }

    func probe(url: URL, attempt: ImportAttempt) async throws -> ImportDiscovery {
        guard try SupportedSource.validateSinglePublicItem(url: url) == .douyin else {
            throw ContentImportError.unsupportedURL
        }
        let page = try await load(url: url, attempt: attempt, contentID: nil)
        let metadata = try Self.metadata(from: page)
        return ImportDiscovery(sourceURL: metadata.sourceURL, primaryItem: metadata)
    }

    func resolveStream(
        for content: ImportedAudioMetadata,
        attempt: ImportAttempt
    ) async throws -> ResolvedAudioStream {
        guard content.platform == .douyin else { throw ContentImportError.unsupportedURL }
        let page = try await load(
            url: content.sourceURL,
            attempt: attempt,
            contentID: content.contentID
        )
        let refreshed = try Self.metadata(from: page)
        guard refreshed.contentID == content.contentID else {
            throw ContentImportError.contentChanged
        }
        guard Self.isApprovedAudioURL(page.audioURL) else {
            throw ContentImportError.mediaUnavailable("抖音没有返回唯一的主视频 AAC 音轨。")
        }

        var headers = [
            "Referer": refreshed.sourceURL.absoluteString,
            "User-Agent": page.userAgent,
        ]
        let visitorCookies = page.cookies.filter(Self.isAllowedVisitorCookie)
        if !visitorCookies.isEmpty {
            headers["Cookie"] =
                visitorCookies
                .map { "\($0.name)=\($0.value)" }
                .joined(separator: "; ")
        }
        return ResolvedAudioStream(
            url: page.audioURL,
            headers: headers,
            duration: refreshed.duration
        )
    }

    private func load(
        url: URL,
        attempt: ImportAttempt,
        contentID: String?
    ) async throws -> DouyinRenderedPage {
        let cookies: [HTTPCookie]
        switch attempt {
        case .anonymous:
            cookies = []
        case .browserRetry(let lease):
            guard Self.sameOperationURL(lease.sourceURL, url),
                lease.consume(source: .douyin, url: url, contentID: contentID)
            else { throw ContentImportError.browserAccessFailed("浏览器访客状态不属于这次抖音操作，已拒绝复用。") }
            cookies = lease.cookies.filter(Self.isAllowedVisitorCookie)
        }

        do {
            return try await pageLoader.load(url: url, cookies: cookies)
        } catch is CancellationError {
            throw ContentImportError.cancelled
        } catch DouyinPageLoadError.challenge {
            switch attempt {
            case .anonymous:
                throw ContentImportError.browserAccessRequired(
                    PlatformVerificationRequest(source: .douyin, url: url)
                )
            case .browserRetry:
                throw ContentImportError.browserAccessFailed("借用访客状态后抖音仍拒绝访问，本次操作已终止。")
            }
        } catch DouyinPageLoadError.restricted {
            throw ContentImportError.restrictedContent("该抖音内容不是可匿名访问的普通公开视频。")
        } catch DouyinPageLoadError.ambiguousAudio {
            throw ContentImportError.mediaUnavailable("抖音页面返回了多个主音轨候选，已安全停止解析。")
        } catch let DouyinPageLoadError.timeout(diagnostic) {
            throw ContentImportError.platformUnavailable("抖音页面加载超时，请稍后重试。（\(diagnostic)）")
        } catch {
            throw ContentImportError.platformUnavailable("抖音页面运行时暂时不可用。")
        }
    }

    private static func metadata(from page: DouyinRenderedPage) throws -> ImportedAudioMetadata {
        guard page.canonicalURL.scheme == "https",
            SupportedSource.source(for: page.canonicalURL) == .douyin,
            let contentID = videoID(from: page.canonicalURL),
            !page.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            isApprovedAudioURL(page.audioURL)
        else { throw ContentImportError.malformedResponse }
        let duration = page.duration.flatMap { value in
            value.isFinite && value > 0 ? value : nil
        }
        return ImportedAudioMetadata(
            platform: .douyin,
            contentID: contentID,
            sourceURL: page.canonicalURL,
            title: page.title,
            author: page.author,
            artworkURL: page.artworkURL,
            duration: duration
        )
    }

    private static func videoID(from url: URL) -> String? {
        let parts = url.path.split(separator: "/")
        guard parts.count == 2,
            parts[0].lowercased() == "video",
            parts[1].allSatisfy(\.isNumber)
        else { return nil }
        return String(parts[1])
    }

    private static func isApprovedAudioURL(_ url: URL) -> Bool {
        guard url.scheme == "https", let host = url.host?.lowercased() else { return false }
        let approvedHost =
            host == "douyinvod.com" || host.hasSuffix(".douyinvod.com")
            || host == "bytecdn.cn" || host.hasSuffix(".bytecdn.cn")
        return approvedHost && url.absoluteString.contains("media-audio-und-mp4a")
    }

    private static func isAllowedVisitorCookie(_ cookie: HTTPCookie) -> Bool {
        let allowedNames = ["ttwid", "s_v_web_id", "msToken"]
        let domain = cookie.domain.lowercased().trimmingCharacters(
            in: CharacterSet(charactersIn: "."))
        let approvedDomain =
            domain == "douyin.com" || domain.hasSuffix(".douyin.com")
            || domain == "iesdouyin.com" || domain.hasSuffix(".iesdouyin.com")
        return approvedDomain && allowedNames.contains(cookie.name)
    }

    private static func sameOperationURL(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs == rhs || (videoID(from: lhs) != nil && videoID(from: lhs) == videoID(from: rhs))
    }
}
