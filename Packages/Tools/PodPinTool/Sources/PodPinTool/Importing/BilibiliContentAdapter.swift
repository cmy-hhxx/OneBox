import Foundation

actor BilibiliContentAdapter: ContentSourceAdapter {
    let source = SupportedSource.bilibili

    private let transport: any HTTPTransporting

    init(transport: any HTTPTransporting = URLSessionHTTPTransport()) {
        self.transport = transport
    }

    func probe(url: URL, attempt: ImportAttempt) async throws -> ImportDiscovery {
        let target = try await videoTarget(from: url)
        let video = try await loadVideo(bvid: target.bvid)
        let selectedPages: [BilibiliPage]
        if let requestedPage = target.page {
            guard let page = video.pages.first(where: { $0.page == requestedPage }) else {
                throw ContentImportError.unsupportedContent("这条 B 站视频没有第 \(requestedPage) 个分 P。")
            }
            selectedPages = [page]
        } else {
            selectedPages = video.pages
        }
        guard !selectedPages.isEmpty else {
            throw ContentImportError.malformedResponse
        }

        let items = selectedPages.map { metadata(for: $0, video: video) }
        return ImportDiscovery(
            sourceURL: canonicalURL(bvid: video.bvid, page: target.page),
            groupTitle: video.pages.count > 1 ? video.title : nil,
            primaryItem: items[0],
            remainingItems: Array(items.dropFirst())
        )
    }

    func resolveStream(
        for content: ImportedAudioMetadata,
        attempt: ImportAttempt
    ) async throws -> ResolvedAudioStream {
        guard content.platform == .bilibili else { throw ContentImportError.unsupportedURL }
        let identity = try identity(from: content)
        let video = try await loadVideo(bvid: identity.bvid)
        guard let page = video.pages.first(where: { $0.page == identity.page }),
            metadata(for: page, video: video).contentID == content.contentID
        else { throw ContentImportError.contentChanged }

        let playURL = try await loadPlayURL(bvid: video.bvid, cid: page.cid)
        let compatibleAudio = playURL.audio
            .filter { audio in
                let codecs = audio.codecs.lowercased()
                return codecs.contains("mp4a") || audio.mimeType.lowercased() == "audio/mp4"
            }
            .sorted { $0.bandwidth > $1.bandwidth }
        guard let audio = compatibleAudio.first,
            let streamURL = URL(string: audio.baseURL),
            Self.isApprovedMediaURL(streamURL)
        else {
            throw ContentImportError.mediaUnavailable("B 站没有返回可播放的 AAC 音轨。")
        }
        return ResolvedAudioStream(
            url: streamURL,
            headers: [
                "Referer": "https://www.bilibili.com/",
                "Origin": "https://www.bilibili.com",
                "User-Agent": Self.userAgent,
            ],
            duration: TimeInterval(page.duration),
            mimeType: audio.mimeType
        )
    }

    private func videoTarget(from sourceURL: URL) async throws -> (bvid: String, page: Int?) {
        guard try SupportedSource.validateSinglePublicItem(url: sourceURL) == .bilibili else {
            throw ContentImportError.unsupportedURL
        }
        var resolvedURL = sourceURL
        if sourceURL.host?.lowercased().hasSuffix("b23.tv") == true {
            var request = URLRequest(url: sourceURL)
            request.timeoutInterval = 15
            request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
            let result = try await transport.data(
                for: request,
                redirectValidator: { original, redirected in
                    original.scheme?.lowercased() == "https"
                        && redirected.scheme?.lowercased() == "https"
                        && redirected.host?.lowercased().hasSuffix(".bilibili.com") == true
                })
            guard (200..<400).contains(result.response.statusCode),
                let redirected = result.response.url,
                redirected.host?.lowercased().hasSuffix(".bilibili.com") == true
            else { throw ContentImportError.platformUnavailable("B 站短链接无法展开。") }
            resolvedURL = redirected
        }

        let components = resolvedURL.path.split(separator: "/")
        guard components.count >= 2,
            components[0].lowercased() == "video",
            Self.isBVID(String(components[1]))
        else { throw ContentImportError.unsupportedURL }
        let page = URLComponents(url: resolvedURL, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "p" })?.value.flatMap(Int.init)
        if let page, page < 1 { throw ContentImportError.unsupportedURL }
        return (String(components[1]), page)
    }

    private func loadVideo(bvid: String) async throws -> BilibiliVideo {
        let endpoint = try apiURL(
            path: "/x/web-interface/view",
            query: [
                URLQueryItem(name: "bvid", value: bvid)
            ])
        let envelope: BilibiliEnvelope<BilibiliVideo> = try await request(endpoint)
        guard envelope.code == 0, let video = envelope.data else {
            if envelope.code == -412 {
                throw ContentImportError.platformUnavailable("B 站暂时拒绝了公开解析请求，请稍后重试。")
            }
            throw ContentImportError.platformUnavailable("B 站暂时无法返回这条公开视频。")
        }
        guard video.bvid == bvid, video.state == 0 else {
            throw ContentImportError.restrictedContent("该 B 站内容不是可公开访问的普通视频。")
        }
        guard video.rights.pay == 0, video.rights.arcPay == 0 else {
            throw ContentImportError.restrictedContent("暂不支持付费或会员 B 站内容。")
        }
        return video
    }

    private func loadPlayURL(bvid: String, cid: Int64) async throws -> BilibiliDash {
        let endpoint = try apiURL(
            path: "/x/player/playurl",
            query: [
                URLQueryItem(name: "bvid", value: bvid),
                URLQueryItem(name: "cid", value: String(cid)),
                URLQueryItem(name: "fnval", value: "16"),
                URLQueryItem(name: "qn", value: "80"),
                URLQueryItem(name: "fourk", value: "1"),
            ])
        let envelope: BilibiliEnvelope<BilibiliPlayData> = try await request(endpoint)
        guard envelope.code == 0, let dash = envelope.data?.dash else {
            if envelope.code == -10403 {
                throw ContentImportError.restrictedContent("该 B 站内容需要受限访问，无法导入。")
            }
            throw ContentImportError.platformUnavailable("B 站暂时无法返回公开音轨。")
        }
        return dash
    }

    private func request<Value: Decodable>(_ url: URL) async throws -> BilibiliEnvelope<Value> {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("https://www.bilibili.com/", forHTTPHeaderField: "Referer")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let result = try await transport.data(for: request)
        guard result.response.statusCode != 412 else {
            throw ContentImportError.platformUnavailable("B 站暂时拒绝了公开解析请求，请稍后重试。")
        }
        guard (200..<300).contains(result.response.statusCode),
            result.response.url?.host?.lowercased() == "api.bilibili.com"
        else { throw ContentImportError.platformUnavailable("B 站公开接口暂时不可用。") }
        do {
            return try JSONDecoder().decode(BilibiliEnvelope<Value>.self, from: result.data)
        } catch {
            throw ContentImportError.malformedResponse
        }
    }

    private func metadata(for page: BilibiliPage, video: BilibiliVideo) -> ImportedAudioMetadata {
        let multipart = video.pages.count > 1
        let title = multipart ? "\(video.title) · P\(page.page) \(page.part)" : video.title
        return ImportedAudioMetadata(
            platform: .bilibili,
            contentID: multipart ? "\(video.bvid)_p\(page.page)" : video.bvid,
            sourceURL: canonicalURL(bvid: video.bvid, page: multipart ? page.page : nil),
            title: title,
            author: video.owner.name,
            artworkURL: Self.secureURL(video.picture),
            duration: TimeInterval(page.duration)
        )
    }

    private func identity(from content: ImportedAudioMetadata) throws -> (bvid: String, page: Int) {
        let segments = content.contentID.components(separatedBy: "_p")
        if segments.count == 2, Self.isBVID(segments[0]), let page = Int(segments[1]), page > 0 {
            return (segments[0], page)
        }
        guard Self.isBVID(content.contentID) else { throw ContentImportError.contentChanged }
        return (content.contentID, 1)
    }

    private func canonicalURL(bvid: String, page: Int?) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.bilibili.com"
        components.path = "/video/\(bvid)"
        if let page { components.queryItems = [URLQueryItem(name: "p", value: String(page))] }
        return components.url!
    }

    private func apiURL(path: String, query: [URLQueryItem]) throws -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.bilibili.com"
        components.path = path
        components.queryItems = query
        guard let url = components.url else { throw ContentImportError.malformedResponse }
        return url
    }

    private static func isBVID(_ value: String) -> Bool {
        value.count >= 10 && value.hasPrefix("BV")
            && value.allSatisfy { $0.isLetter || $0.isNumber }
    }

    private static func secureURL(_ value: String) -> URL? {
        guard var components = URLComponents(string: value) else { return nil }
        if components.scheme == "http" { components.scheme = "https" }
        return components.scheme == "https" ? components.url : nil
    }

    private static func isApprovedMediaURL(_ url: URL) -> Bool {
        guard url.scheme == "https", let host = url.host?.lowercased() else { return false }
        return host == "bilivideo.com" || host.hasSuffix(".bilivideo.com")
            || host == "bilivideo.cn" || host.hasSuffix(".bilivideo.cn")
    }

    private static let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 Version/18.0 Safari/605.1.15"
}

private struct BilibiliEnvelope<Value: Decodable>: Decodable {
    let code: Int
    let message: String?
    let data: Value?
}

private struct BilibiliVideo: Decodable {
    let bvid: String
    let title: String
    let picture: String
    let state: Int
    let owner: BilibiliOwner
    let rights: BilibiliRights
    let pages: [BilibiliPage]

    enum CodingKeys: String, CodingKey {
        case bvid, title, state, owner, rights, pages
        case picture = "pic"
    }
}

private struct BilibiliOwner: Decodable {
    let name: String
}

private struct BilibiliRights: Decodable {
    let pay: Int
    let arcPay: Int

    enum CodingKeys: String, CodingKey {
        case pay
        case arcPay = "arc_pay"
    }
}

private struct BilibiliPage: Decodable {
    let cid: Int64
    let page: Int
    let part: String
    let duration: Int
}

private struct BilibiliPlayData: Decodable {
    let dash: BilibiliDash?
}

private struct BilibiliDash: Decodable {
    let audio: [BilibiliAudio]
}

private struct BilibiliAudio: Decodable {
    let baseURL: String
    let bandwidth: Int
    let mimeType: String
    let codecs: String

    enum CodingKeys: String, CodingKey {
        case baseURL = "baseUrl"
        case bandwidth, mimeType, codecs
    }
}
