import Foundation
@preconcurrency import WebKit

struct DouyinWebPageLoader: DouyinRenderedPageLoading {
    func load(url: URL, cookies: [HTTPCookie]) async throws -> DouyinRenderedPage {
        try await DouyinWebSession.render(url: url, cookies: cookies)
    }
}

@MainActor
private final class DouyinWebSession: NSObject, WKNavigationDelegate {
    private let sourceURL: URL
    private let cookies: [HTTPCookie]
    private let dataStore: WKWebsiteDataStore
    private let webView: WKWebView
    private let timeoutTaskOwner = CooperativeTaskOwner()
    private var navigationContinuation: CheckedContinuation<Void, Error>?
    private var rejectedNavigation = false
    private var isDestroyed = false

    private init(sourceURL: URL, cookies: [HTTPCookie]) {
        self.sourceURL = sourceURL
        self.cookies = cookies
        dataStore = .nonPersistent()

        let controller = WKUserContentController()
        controller.addUserScript(
            WKUserScript(
                source: Self.resourceObserverScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            ))
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = dataStore
        configuration.userContentController = controller
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        webView = WKWebView(
            frame: CGRect(x: 0, y: 0, width: 1280, height: 720),
            configuration: configuration
        )
        super.init()
        webView.customUserAgent = Self.userAgent
        webView.navigationDelegate = self
    }

    static func render(url: URL, cookies: [HTTPCookie]) async throws -> DouyinRenderedPage {
        let session = DouyinWebSession(sourceURL: url, cookies: cookies)
        return try await session.run()
    }

    private func run() async throws -> DouyinRenderedPage {
        defer { destroy() }
        return try await withTaskCancellationHandler {
            for cookie in cookies {
                try Task.checkCancellation()
                try await set(cookie: cookie)
            }
            try Task.checkCancellation()
            try await loadInitialPage()

            var lastSnapshot: Snapshot?
            for _ in 0..<50 {
                try Task.checkCancellation()
                if rejectedNavigation { throw DouyinPageLoadError.navigation }
                let snapshot = try await readSnapshot()
                lastSnapshot = snapshot
                if !snapshot.restrictedReasons.isEmpty {
                    throw DouyinPageLoadError.restricted(snapshot.restrictedReasons)
                }
                if !snapshot.challengeReasons.isEmpty {
                    throw DouyinPageLoadError.challenge(snapshot.challengeReasons)
                }
                if snapshot.audioURLs.count > 1 {
                    throw DouyinPageLoadError.ambiguousAudio(snapshot.audioDiagnostic)
                }
                if let rendered = try await renderedPage(from: snapshot) {
                    return rendered
                }
                _ = try? await evaluateJavaScript(
                    "document.querySelector('video')?.play().catch(() => {})",
                    timeout: .seconds(1)
                )
                try await Task.sleep(for: .milliseconds(400))
            }
            throw DouyinPageLoadError.timeout(lastSnapshot?.diagnostic ?? "no-snapshot")
        } onCancel: {
            Task { @MainActor [weak self] in self?.destroy() }
        }
    }

    private func loadInitialPage() async throws {
        try Task.checkCancellation()
        guard !isDestroyed else { throw CancellationError() }
        var request = URLRequest(
            url: sourceURL,
            cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
            timeoutInterval: 20
        )
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        let result = await withCooperativeTimeout(
            .seconds(20),
            owner: timeoutTaskOwner
        ) { @MainActor [weak self] in
            guard let self, !isDestroyed else { return WebKitWaitResult.cancelled }
            do {
                try await withCheckedThrowingContinuation { continuation in
                    navigationContinuation = continuation
                    webView.load(request)
                }
                return .completed
            } catch is CancellationError {
                return .cancelled
            } catch {
                return .failed(error)
            }
        }
        switch result {
        case .value(.completed):
            return
        case .value(.cancelled):
            throw CancellationError()
        case .value(.failed(let error)):
            throw error
        case .timedOut:
            try Task.checkCancellation()
            throw DouyinPageLoadError.timeout("initial-navigation")
        }
    }

    private func renderedPage(from snapshot: Snapshot) async throws -> DouyinRenderedPage? {
        guard let canonical = snapshot.canonical.flatMap(URL.init(string:)),
            let title = snapshot.title?.trimmedNonEmpty,
            snapshot.audioURLs.count == 1,
            let audioURL = URL(string: snapshot.audioURLs[0]),
            let userAgent = snapshot.userAgent?.trimmedNonEmpty
        else { return nil }
        let artworkURL = snapshot.artwork.flatMap(URL.init(string:))
        let pageCookies = try await allCookies()
        let duration = snapshot.duration.flatMap { value in
            value.isFinite && value > 0 ? value : nil
        }
        return DouyinRenderedPage(
            canonicalURL: canonical,
            title: title,
            author: snapshot.author?.trimmedNonEmpty,
            artworkURL: artworkURL,
            duration: duration,
            audioURL: audioURL,
            userAgent: userAgent,
            cookies: pageCookies
        )
    }

    private func evaluateJavaScript(_ script: String, timeout: Duration) async throws -> Any? {
        let result = await withCooperativeTimeout(timeout, owner: timeoutTaskOwner) {
            @MainActor [weak self] in
            guard let self, !isDestroyed else { return WebKitJavaScriptResult.cancelled }
            do {
                let value = try await webView.evaluateJavaScript(script)
                return WebKitJavaScriptResult.value(value)
            } catch is CancellationError {
                return WebKitJavaScriptResult.cancelled
            } catch {
                return WebKitJavaScriptResult.failed(error)
            }
        }
        switch result {
        case .timedOut:
            try Task.checkCancellation()
            throw DouyinPageLoadError.timeout("javascript")
        case .value(.cancelled):
            throw CancellationError()
        case .value(.failed(let error)):
            throw error
        case .value(.value(let value)):
            return value
        }
    }

    private func readSnapshot() async throws -> Snapshot {
        let value = try await evaluateJavaScript(Self.snapshotScript, timeout: .seconds(5))
        guard let json = value as? String, let data = json.data(using: .utf8) else {
            throw ContentImportError.malformedResponse
        }
        do {
            return try JSONDecoder().decode(Snapshot.self, from: data)
        } catch {
            throw ContentImportError.malformedResponse
        }
    }

    private func set(cookie: HTTPCookie) async throws {
        try Task.checkCancellation()
        guard !isDestroyed else { throw CancellationError() }
        let result = await withCooperativeTimeout(
            .seconds(5),
            owner: timeoutTaskOwner
        ) { @MainActor [dataStore] in
            await withCheckedContinuation { continuation in
                dataStore.httpCookieStore.setCookie(cookie) {
                    continuation.resume()
                }
            }
        }
        guard case .value = result else {
            try Task.checkCancellation()
            throw DouyinPageLoadError.timeout("cookie-set")
        }
        try Task.checkCancellation()
    }

    private func allCookies() async throws -> [HTTPCookie] {
        try Task.checkCancellation()
        guard !isDestroyed else { throw CancellationError() }
        let result = await withCooperativeTimeout(
            .seconds(5),
            owner: timeoutTaskOwner
        ) { @MainActor [dataStore] in
            await withCheckedContinuation { continuation in
                dataStore.httpCookieStore.getAllCookies { cookies in
                    continuation.resume(returning: cookies)
                }
            }
        }
        switch result {
        case .value(let cookies):
            try Task.checkCancellation()
            return cookies
        case .timedOut:
            try Task.checkCancellation()
            throw DouyinPageLoadError.timeout("cookie-read")
        }
    }

    private func destroy() {
        guard !isDestroyed else { return }
        isDestroyed = true
        timeoutTaskOwner.cancelAll()
        webView.stopLoading()
        webView.navigationDelegate = nil
        if let continuation = navigationContinuation {
            navigationContinuation = nil
            continuation.resume(throwing: CancellationError())
        }
    }

    private enum WebKitJavaScriptResult: @unchecked Sendable {
        case value(Any?)
        case cancelled
        case failed(any Error)
    }

    private enum WebKitWaitResult: @unchecked Sendable {
        case completed
        case cancelled
        case failed(any Error)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        navigationContinuation?.resume()
        navigationContinuation = nil
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: any Error
    ) {
        navigationContinuation?.resume(throwing: error)
        navigationContinuation = nil
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: any Error
    ) {
        navigationContinuation?.resume(throwing: error)
        navigationContinuation = nil
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
    ) {
        guard navigationAction.targetFrame?.isMainFrame != false else {
            decisionHandler(.allow)
            return
        }
        guard let url = navigationAction.request.url,
            SupportedSource.douyin.acceptsVerificationNavigation(to: url)
        else {
            rejectedNavigation = true
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    private struct Snapshot: Decodable {
        let canonical: String?
        let title: String?
        let author: String?
        let artwork: String?
        let duration: TimeInterval?
        let audioURLs: [String]
        let audioOffsets: [Double]
        let userAgent: String?
        let challengeReasons: [String]
        let restrictedReasons: [String]

        var diagnostic: String {
            [
                "canonical=\(canonical != nil)",
                "title=\(title != nil)",
                "author=\(author != nil)",
                "duration=\(duration != nil)",
                "audio=\(audioURLs.count)",
                "challenge=\(challengeReasons.joined(separator: "+"))",
                "restricted=\(restrictedReasons.joined(separator: "+"))",
            ].joined(separator: ",")
        }

        var audioDiagnostic: String {
            "count=\(audioURLs.count),offsets=\(audioOffsets.map { String(Int($0)) }.joined(separator: "+"))"
        }
    }

    private static let resourceObserverScript = #"""
        (() => {
          window.__podpinResources = [];
          const record = (entry) => {
            if (typeof entry?.name === 'string' && entry.name.length > 0) {
              window.__podpinResources.push({ url: entry.name, at: entry.startTime || 0 });
            }
          };
          try {
            new PerformanceObserver((list) => list.getEntries().forEach(record))
              .observe({ entryTypes: ['resource'] });
          } catch (_) {}
        })();
        """#

    private static let snapshotScript = #"""
        (() => {
          const meta = (selector) => document.querySelector(selector)?.content || null;
          const resources = [
            ...(window.__podpinResources || []),
            ...performance.getEntriesByType('resource').map((entry) => ({
              url: entry.name,
              at: entry.startTime || 0
            }))
          ];
          const audioResources = resources
            .filter((entry) => typeof entry?.url === 'string' && entry.url.includes('media-audio-und-mp4a'))
            .sort((lhs, rhs) => lhs.at - rhs.at);
          const firstAudioAt = audioResources[0]?.at ?? null;
          const primaryAudioResources = firstAudioAt === null
            ? []
            : audioResources.filter((entry) => entry.at <= firstAudioAt + 500);
          const audioByPath = new Map();
          for (const entry of primaryAudioResources) {
            try {
              const url = entry.url;
              const pathComponents = new URL(url).pathname.split('/').filter(Boolean);
              const mediaIdentity = pathComponents.slice(-2).join('/');
              if (!audioByPath.has(mediaIdentity)) audioByPath.set(mediaIdentity, entry);
            } catch (_) {}
          }
          const primaryAudioEntries = [...audioByPath.values()];
          const audioURLs = primaryAudioEntries.map((entry) => entry.url);
          const audioOffsets = primaryAudioEntries.map((entry) => entry.at - firstAudioAt);
          const path = location.pathname || '';
          const videoID = path.match(/^\/video\/(\d+)/)?.[1] || null;

          let breadcrumbAuthor = null;
          let structuredTitle = null;
          let structuredArtwork = null;
          let structuredDuration = null;
          for (const node of document.querySelectorAll('script[type="application/ld+json"]')) {
            try {
              const value = JSON.parse(node.textContent || 'null');
              const entries = Array.isArray(value) ? value : [value];
              for (const entry of entries) {
                if (entry?.['@type'] === 'VideoObject') {
                  structuredTitle = entry.name || entry.headline || structuredTitle;
                  const thumbnail = Array.isArray(entry.thumbnailUrl) ? entry.thumbnailUrl[0] : entry.thumbnailUrl;
                  structuredArtwork = thumbnail || structuredArtwork;
                  breadcrumbAuthor = entry.author?.name || entry.creator?.name || breadcrumbAuthor;
                }
                if (entry?.['@type'] === 'BreadcrumbList' && Array.isArray(entry.itemListElement)) {
                  const names = entry.itemListElement
                    .map((item) => item?.name || item?.item?.name)
                    .filter((name) => typeof name === 'string' && name.length > 0);
                  if (names.length > 0) breadcrumbAuthor = names[0];
                }
              }
            } catch (_) {}
          }

          const seen = new WeakSet();
          let inspectedNodes = 0;
          const inspectStructuredValue = (value, depth = 0) => {
            if (!value || typeof value !== 'object' || depth > 10 || inspectedNodes > 50000) return;
            if (seen.has(value)) return;
            seen.add(value);
            inspectedNodes += 1;

            const candidateID = String(value.aweme_id || value.awemeId || value.awemeID || '');
            if (videoID && candidateID === videoID) {
              structuredTitle = value.desc || value.title || structuredTitle;
              breadcrumbAuthor = value.author?.nickname
                || value.author?.nickName
                || value.author?.name
                || breadcrumbAuthor;
              const rawDuration = Number(value.video?.duration || value.duration || 0);
              if (Number.isFinite(rawDuration) && rawDuration > 0) {
                structuredDuration = rawDuration > 10000 ? rawDuration / 1000 : rawDuration;
              }
              structuredArtwork = value.video?.cover?.url_list?.[0]
                || value.video?.origin_cover?.url_list?.[0]
                || structuredArtwork;
            }

            for (const child of Object.values(value)) inspectStructuredValue(child, depth + 1);
          };
          for (const value of [window._ROUTER_DATA, window.__INITIAL_STATE__, window.__NEXT_DATA__]) {
            try { inspectStructuredValue(value); } catch (_) {}
          }
          for (const node of document.querySelectorAll(
            'script[type="application/json"], script#RENDER_DATA, script#__NEXT_DATA__'
          )) {
            const raw = node.textContent || '';
            for (const candidate of [raw, (() => {
              try { return decodeURIComponent(raw); } catch (_) { return ''; }
            })()]) {
              try { inspectStructuredValue(JSON.parse(candidate)); } catch (_) {}
            }
          }

          const text = (document.body?.innerText || '').slice(0, 12000);
          const challengeElement = [...document.querySelectorAll(
            'iframe[src*="captcha"], [id*="captcha"], [class*="captcha"]'
          )].some((element) => element.getClientRects().length > 0);
          const challengeReasons = [];
          if (challengeElement) challengeReasons.push('visible-element');
          if (/请完成下列验证/.test(text)) challengeReasons.push('text-complete-challenge');
          if (/拖动滑块/.test(text)) challengeReasons.push('text-slider');
          if (/安全验证/.test(text)) challengeReasons.push('text-security-check');
          if (/verify|captcha/i.test(path)) challengeReasons.push('navigation-path');
          const restrictedReasons = [];
          if (/作品已删除/.test(text)) restrictedReasons.push('text-deleted');
          if (/作品不存在/.test(text)) restrictedReasons.push('text-missing');
          if (/私密作品/.test(text)) restrictedReasons.push('text-private');
          if (/暂无权限/.test(text)) restrictedReasons.push('text-no-permission');
          if (/登录后查看/.test(text)) restrictedReasons.push('text-login-to-view');
          if (/内容不可见/.test(text)) restrictedReasons.push('text-unavailable');
          if (/passport|login/i.test(path)) restrictedReasons.push('navigation-login');
          const videos = [...document.querySelectorAll('video')];
          const visibleVideos = videos
            .map((video) => ({
              video,
              area: Math.max(0, video.getBoundingClientRect().width)
                * Math.max(0, video.getBoundingClientRect().height)
            }))
            .filter((entry) => entry.area > 0)
            .sort((lhs, rhs) => rhs.area - lhs.area);
          const video = visibleVideos[0]?.video || videos.find((candidate) =>
            Number.isFinite(candidate.duration) && candidate.duration > 0
          );
          let duration = Number.isFinite(video?.duration) && video.duration > 0
            ? video.duration
            : structuredDuration;
          if (!(Number.isFinite(duration) && duration > 0) && audioURLs.length === 1) {
            const probeID = '__podpinAudioDurationProbe';
            let probe = document.getElementById(probeID);
            if (!probe) {
              probe = document.createElement('audio');
              probe.id = probeID;
              probe.preload = 'metadata';
              probe.style.display = 'none';
              probe.src = audioURLs[0];
              document.documentElement.appendChild(probe);
            }
            if (Number.isFinite(probe.duration) && probe.duration > 0) duration = probe.duration;
          }
          const canonicalLocation = /^\/video\/\d+/.test(path) ? location.href : null;
          return JSON.stringify({
            canonical: document.querySelector('link[rel="canonical"]')?.href
              || meta('meta[property="og:url"]')
              || canonicalLocation,
            title: meta('meta[name="lark:url:video_title"]')
              || meta('meta[property="og:title"]')
              || structuredTitle
              || document.title
              || (videoID ? `抖音视频 ${videoID}` : null),
            author: meta('meta[name="lark:url:author_name"]')
              || meta('meta[name="author"]')
              || breadcrumbAuthor,
            artwork: meta('meta[name="lark:url:video_cover_image_url"]')
              || meta('meta[property="og:image"]')
              || structuredArtwork,
            duration,
            audioURLs,
            audioOffsets,
            userAgent: navigator.userAgent,
            challengeReasons,
            restrictedReasons
          });
        })()
        """#

    private static let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 Version/18.0 Safari/605.1.15"
}

extension String {
    fileprivate var trimmedNonEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
