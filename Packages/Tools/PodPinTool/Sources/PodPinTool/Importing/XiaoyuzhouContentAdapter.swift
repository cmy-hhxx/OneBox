import Foundation

actor XiaoyuzhouContentAdapter: ContentSourceAdapter {
    let source = SupportedSource.xiaoyuzhou

    private let transport: any HTTPTransporting

    init(transport: any HTTPTransporting = URLSessionHTTPTransport()) {
        self.transport = transport
    }

    func probe(url: URL, attempt: ImportAttempt) async throws -> ImportDiscovery {
        let episode = try await loadEpisode(from: url)
        let metadata = episode.metadata
        return ImportDiscovery(sourceURL: metadata.sourceURL, primaryItem: metadata)
    }

    func resolveStream(
        for content: ImportedAudioMetadata,
        attempt: ImportAttempt
    ) async throws -> ResolvedAudioStream {
        guard content.platform == .xiaoyuzhou else {
            throw ContentImportError.unsupportedURL
        }
        let episode = try await loadEpisode(from: content.sourceURL)
        guard episode.metadata.contentID == content.contentID else {
            throw ContentImportError.contentChanged
        }
        var validationRequest = URLRequest(url: episode.audioURL)
        validationRequest.httpMethod = "HEAD"
        validationRequest.timeoutInterval = 15
        validationRequest.setValue(
            episode.metadata.sourceURL.absoluteString, forHTTPHeaderField: "Referer")
        let validation = try await transport.data(
            for: validationRequest,
            redirectValidator: { _, redirected in
                Self.isApprovedMediaURL(redirected)
            })
        guard (200..<400).contains(validation.response.statusCode),
            let finalURL = validation.response.url,
            Self.isApprovedMediaURL(finalURL)
        else {
            throw ContentImportError.mediaUnavailable("小宇宙音频重定向到了不受支持的地址。")
        }
        return ResolvedAudioStream(
            url: finalURL,
            headers: ["Referer": episode.metadata.sourceURL.absoluteString],
            duration: episode.metadata.duration
        )
    }

    private func loadEpisode(from url: URL) async throws -> XiaoyuzhouEpisode {
        guard try SupportedSource.validateSinglePublicItem(url: url) == .xiaoyuzhou,
            let episodeID = url.path.split(separator: "/").last.map(String.init)
        else { throw ContentImportError.unsupportedURL }

        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        let result = try await transport.data(for: request)
        guard result.response.statusCode == 200,
            let finalURL = result.response.url,
            SupportedSource.source(for: finalURL) == .xiaoyuzhou,
            let html = String(data: result.data, encoding: .utf8)
        else {
            throw ContentImportError.platformUnavailable("小宇宙暂时无法返回这条公开单集。")
        }

        let episode = try Self.decodeEpisode(from: html, expectedID: episodeID, sourceURL: url)
        guard episode.status == "NORMAL", !episode.isPrivateMedia else {
            throw ContentImportError.restrictedContent("该小宇宙单集不是可公开访问的普通节目。")
        }
        guard Self.isApprovedMediaURL(episode.audioURL) else {
            throw ContentImportError.mediaUnavailable("小宇宙返回了不受支持的音频地址。")
        }
        return episode
    }

    private static func decodeEpisode(
        from html: String,
        expectedID: String,
        sourceURL: URL
    ) throws -> XiaoyuzhouEpisode {
        guard let marker = html.range(of: "<script id=\"__NEXT_DATA__\""),
            let openingEnd = html[marker.upperBound...].firstIndex(of: ">"),
            let closing = html.range(of: "</script>", range: openingEnd..<html.endIndex),
            let data = String(html[html.index(after: openingEnd)..<closing.lowerBound]).data(
                using: .utf8),
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let props = root["props"] as? [String: Any],
            let pageProps = props["pageProps"] as? [String: Any],
            let raw = pageProps["episode"] as? [String: Any],
            raw["eid"] as? String == expectedID,
            let title = (raw["title"] as? String)?.trimmedNonEmpty,
            let duration = Self.timeInterval(raw["duration"]), duration > 0,
            let enclosure = raw["enclosure"] as? [String: Any],
            let audioURLString = enclosure["url"] as? String,
            let audioURL = URL(string: audioURLString)
        else { throw ContentImportError.malformedResponse }

        let podcast = raw["podcast"] as? [String: Any] ?? [:]
        let jsonLD = Self.podcastEpisodeJSONLD(from: html)
        let podcastTitle =
            (podcast["title"] as? String)?.trimmedNonEmpty
            ?? ((jsonLD?["partOfSeries"] as? [String: Any])?["name"] as? String)?.trimmedNonEmpty
        guard let podcastTitle else { throw ContentImportError.malformedResponse }
        let artworkURL =
            Self.artworkURL(from: raw, podcast: podcast)
            ?? Self.jsonLDArtworkURL(jsonLD)
        let canonicalURL =
            URL(string: "https://www.xiaoyuzhoufm.com/episode/\(expectedID)") ?? sourceURL
        return XiaoyuzhouEpisode(
            metadata: ImportedAudioMetadata(
                platform: .xiaoyuzhou,
                contentID: expectedID,
                sourceURL: canonicalURL,
                title: title,
                author: podcastTitle,
                artworkURL: artworkURL,
                duration: duration
            ),
            audioURL: audioURL,
            status: raw["status"] as? String,
            isPrivateMedia: raw["isPrivateMedia"] as? Bool == true
        )
    }

    private static func artworkURL(
        from episode: [String: Any],
        podcast: [String: Any]
    ) -> URL? {
        let candidates: [[String: Any]?] = [
            episode["image"] as? [String: Any],
            podcast["image"] as? [String: Any],
            podcast["avatar"] as? [String: Any],
        ]
        for candidate in candidates.compactMap({ $0 }) {
            let picture = (candidate["picture"] as? [String: Any]) ?? candidate
            if let value = picture["picUrl"] as? String, let url = URL(string: value) {
                return url
            }
        }
        return nil
    }

    private static func podcastEpisodeJSONLD(from html: String) -> [String: Any]? {
        let pattern = #"(?is)<script[^>]*type=["']application/ld\+json["'][^>]*>(.*?)</script>"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return nil }
        let fullRange = NSRange(html.startIndex..<html.endIndex, in: html)
        for match in expression.matches(in: html, range: fullRange) {
            guard match.numberOfRanges > 1,
                let range = Range(match.range(at: 1), in: html),
                let data = String(html[range]).data(using: .utf8),
                let object = try? JSONSerialization.jsonObject(with: data)
            else { continue }
            if let episode = firstPodcastEpisode(in: object) {
                return episode
            }
        }
        return nil
    }

    private static func firstPodcastEpisode(in object: Any) -> [String: Any]? {
        if let values = object as? [Any] {
            return values.lazy.compactMap(firstPodcastEpisode).first
        }
        guard let value = object as? [String: Any] else { return nil }
        let types =
            if let type = value["@type"] as? String {
                [type]
            } else {
                value["@type"] as? [String] ?? []
            }
        if types.contains("PodcastEpisode") { return value }
        if let graph = value["@graph"] as? [Any] {
            return graph.lazy.compactMap(firstPodcastEpisode).first
        }
        return nil
    }

    private static func jsonLDArtworkURL(_ jsonLD: [String: Any]?) -> URL? {
        let value: String?
        if let image = jsonLD?["image"] as? String {
            value = image
        } else if let image = jsonLD?["image"] as? [String: Any] {
            value = image["url"] as? String ?? image["contentUrl"] as? String
        } else {
            value = nil
        }
        guard let value, let url = URL(string: value), url.scheme == "https" else { return nil }
        return url
    }

    private static func timeInterval(_ value: Any?) -> TimeInterval? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String { return TimeInterval(string) }
        return nil
    }

    private static func isApprovedMediaURL(_ url: URL) -> Bool {
        guard url.scheme == "https", let host = url.host?.lowercased() else { return false }
        return host == "media.xyzcdn.net" || host.hasSuffix(".media.xyzcdn.net")
    }

    private static let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 Version/18.0 Safari/605.1.15"
}

private struct XiaoyuzhouEpisode: Sendable {
    let metadata: ImportedAudioMetadata
    let audioURL: URL
    let status: String?
    let isPrivateMedia: Bool
}

extension String {
    fileprivate var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
