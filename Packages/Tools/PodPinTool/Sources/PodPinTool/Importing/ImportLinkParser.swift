import Foundation

/// A source-shaped representation of pasted text. Keeping all candidates makes
/// the single-item UI honest today and gives a future batch queue a stable
/// input seam without changing the importer protocol.
struct ImportLinkCandidates: Equatable, Sendable {
    let urls: [URL]
    let detectedHTTPSURLCount: Int
    let suggestedTitle: String?

    var hasExactlyOneSupportedURL: Bool { urls.count == 1 }
}

enum ImportLinkParser {
    static func candidates(in pastedText: String) -> ImportLinkCandidates {
        let range = NSRange(pastedText.startIndex..., in: pastedText)
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let matches = detector?.matches(in: pastedText, options: [], range: range) ?? []

        var urls: [URL] = []
        var seen = Set<String>()
        var detectedHTTPSURLCount = 0

        for match in matches {
            guard let matchRange = Range(match.range, in: pastedText) else { continue }
            let rawURL = String(pastedText[matchRange]).trimmingTrailingLinkPunctuation()
            guard let url = URL(string: rawURL), url.scheme?.lowercased() == "https" else {
                continue
            }
            detectedHTTPSURLCount += 1
            guard SupportedSource.source(for: url) != nil else { continue }

            let identity = normalizedIdentity(for: url)
            guard seen.insert(identity).inserted else { continue }
            urls.append(url)
        }

        let suggestedTitle =
            urls.count == 1 && SupportedSource.source(for: urls[0]) == .douyin
            ? douyinShareTitle(in: pastedText, before: urls[0])
            : nil
        return ImportLinkCandidates(
            urls: urls,
            detectedHTTPSURLCount: detectedHTTPSURLCount,
            suggestedTitle: suggestedTitle
        )
    }

    private static func douyinShareTitle(in pastedText: String, before url: URL) -> String? {
        guard let urlRange = pastedText.range(of: url.absoluteString) else { return nil }
        var prefix = String(pastedText[..<urlRange.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let hashtag = prefix.range(of: #"\s+#"#, options: .regularExpression) {
            prefix = String(prefix[..<hashtag.lowerBound])
        }
        if let closingBracket = prefix.lastIndex(of: "】") {
            prefix = String(prefix[prefix.index(after: closingBracket)...])
        } else if let firstCJK = prefix.firstIndex(where: { character in
            character.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) }
        }) {
            prefix = String(prefix[firstCJK...])
        }
        let title = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.count >= 2 ? title : nil
    }

    private static func normalizedIdentity(for url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.absoluteString
        }
        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        components.fragment = nil
        return components.string ?? url.absoluteString
    }
}

extension String {
    fileprivate func trimmingTrailingLinkPunctuation() -> String {
        let trailingPunctuation = CharacterSet(charactersIn: ".,;:!?，。；：！？、）】》〉』」”’\"'")
        return trimmingCharacters(in: trailingPunctuation)
    }
}
