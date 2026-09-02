import Foundation

actor FiresideContentAdapter: ContentSourceAdapter {
    let source = SupportedSource.fireside

    private let transport: any HTTPTransporting

    init(transport: any HTTPTransporting = URLSessionHTTPTransport()) {
        self.transport = transport
    }

    func probe(url: URL, attempt: ImportAttempt) async throws -> ImportDiscovery {
        let episode = try await loadEpisode(from: url)
        return ImportDiscovery(sourceURL: episode.metadata.sourceURL, primaryItem: episode.metadata)
    }

    func resolveStream(
        for content: ImportedAudioMetadata,
        attempt: ImportAttempt
    ) async throws -> ResolvedAudioStream {
        guard content.platform == .fireside else {
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
            episode.metadata.sourceURL.absoluteString,
            forHTTPHeaderField: "Referer"
        )
        let validation = try await transport.data(
            for: validationRequest,
            redirectValidator: { _, redirected in
                Self.isApprovedMediaURL(redirected)
            })
        guard (200..<400).contains(validation.response.statusCode),
            let finalURL = validation.response.url,
            Self.isApprovedMediaURL(finalURL)
        else {
            throw ContentImportError.mediaUnavailable("Fireside 音频重定向到了不受支持的地址。")
        }

        return ResolvedAudioStream(
            url: finalURL,
            headers: ["Referer": episode.metadata.sourceURL.absoluteString],
            duration: episode.metadata.duration,
            mimeType: Self.mimeType(for: finalURL)
        )
    }

    private func loadEpisode(from url: URL) async throws -> FiresideEpisode {
        guard try SupportedSource.validateSinglePublicItem(url: url) == .fireside,
            let expectedContentID = Self.contentID(for: url)
        else { throw ContentImportError.unsupportedURL }

        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        let result = try await transport.data(for: request)
        guard result.response.statusCode == 200,
            let finalURL = result.response.url,
            SupportedSource.source(for: finalURL) == .fireside,
            let html = String(data: result.data, encoding: .utf8)
        else {
            throw ContentImportError.platformUnavailable("Fireside 暂时无法返回这条公开单集。")
        }

        let episode = try Self.decodeEpisode(from: html)
        guard episode.metadata.contentID == expectedContentID else {
            throw ContentImportError.contentChanged
        }
        guard Self.isApprovedMediaURL(episode.audioURL) else {
            throw ContentImportError.mediaUnavailable("Fireside 返回了不受支持的音频地址。")
        }
        return episode
    }

    private static func decodeEpisode(from html: String) throws -> FiresideEpisode {
        guard let raw = podcastEpisodeJSONLD(from: html),
            let title = trimmedNonEmpty(raw["name"] as? String),
            let canonicalURLString = raw["url"] as? String,
            let canonicalURL = URL(string: canonicalURLString),
            try SupportedSource.validateSinglePublicItem(url: canonicalURL) == .fireside,
            let contentID = contentID(for: canonicalURL),
            let durationString = raw["timeRequired"] as? String,
            let duration = duration(from: durationString),
            duration > 0,
            let series = raw["partOfSeries"] as? [String: Any],
            let author = trimmedNonEmpty(series["name"] as? String),
            let media = raw["associatedMedia"] as? [String: Any],
            let audioURLString = media["contentUrl"] as? String,
            let audioURL = URL(string: audioURLString)
        else { throw ContentImportError.malformedResponse }

        let artworkURL = (raw["image"] as? String).flatMap(secureURL(from:))
        return FiresideEpisode(
            metadata: ImportedAudioMetadata(
                platform: .fireside,
                contentID: contentID,
                sourceURL: canonicalURL,
                title: title,
                author: author,
                artworkURL: artworkURL,
                duration: duration
            ),
            audioURL: audioURL
        )
    }

    private static func podcastEpisodeJSONLD(from html: String) -> [String: Any]? {
        let pattern = #"(?is)<script[^>]*type=["']application/ld\+json["'][^>]*>(.*?)</script>"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)

        for match in expression.matches(in: html, range: range) {
            guard match.numberOfRanges > 1,
                let jsonRange = Range(match.range(at: 1), in: html),
                let data = String(html[jsonRange]).data(using: .utf8),
                let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                isPodcastEpisode(raw["@type"])
            else { continue }
            return raw
        }
        return nil
    }

    private static func isPodcastEpisode(_ rawType: Any?) -> Bool {
        if let type = rawType as? String {
            return type == "PodcastEpisode"
        }
        if let types = rawType as? [String] {
            return types.contains("PodcastEpisode")
        }
        return false
    }

    private static func duration(from value: String) -> TimeInterval? {
        let pattern = #"^PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+(?:\.\d+)?)S)?$"#
        guard let expression = try? NSRegularExpression(pattern: pattern),
            let match = expression.firstMatch(
                in: value,
                range: NSRange(value.startIndex..<value.endIndex, in: value)
            ),
            match.range == NSRange(value.startIndex..<value.endIndex, in: value)
        else { return nil }

        func component(at index: Int) -> Double {
            guard match.range(at: index).location != NSNotFound,
                let range = Range(match.range(at: index), in: value)
            else { return 0 }
            return Double(value[range]) ?? 0
        }

        let duration =
            component(at: 1) * 3_600
            + component(at: 2) * 60
            + component(at: 3)
        return duration > 0 ? duration : nil
    }

    private static func contentID(for url: URL) -> String? {
        guard let host = url.host?.lowercased() else { return nil }
        let pathComponents = url.path.split(separator: "/", omittingEmptySubsequences: true)
        guard pathComponents.count == 1 else { return nil }
        return "\(host)/\(pathComponents[0])"
    }

    private static func trimmedNonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func secureURL(from value: String) -> URL? {
        guard let url = URL(string: value), url.scheme?.lowercased() == "https" else { return nil }
        return url
    }

    private static func isApprovedMediaURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https",
            let host = url.host?.lowercased(),
            ["mp3", "m4a"].contains(url.pathExtension.lowercased())
        else { return false }

        if host == "aphid.fireside.fm" { return true }
        guard host.hasSuffix(".fireside.fm") else { return false }
        let subdomain = host.dropLast(".fireside.fm".count)
        guard subdomain.hasPrefix("media") else { return false }
        return subdomain.dropFirst("media".count).allSatisfy(\.isNumber)
    }

    private static func mimeType(for url: URL) -> String {
        url.pathExtension.lowercased() == "m4a" ? "audio/mp4" : "audio/mpeg"
    }

    private static let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 Version/18.0 Safari/605.1.15"
}

private struct FiresideEpisode: Sendable {
    let metadata: ImportedAudioMetadata
    let audioURL: URL
}
