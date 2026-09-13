import AppKit
import OneBoxDesignSystem
import SwiftUI

/// Bounded ImageIO thumbnail decoding keeps source-sized artwork and cache
/// work off the scrolling list's main-actor body.
struct ArtworkThumbnailView: View {
    let url: URL?
    let maxPixelSize: Int
    let placeholderFont: Font
    @State private var image: NSImage?
    @State private var timeoutTaskOwner = CooperativeTaskOwner()

    @Environment(\.designPalette) private var palette

    init(
        url: URL?,
        maxPixelSize: Int = 120,
        placeholderFont: Font = DesignTypography.sectionTitle
    ) {
        self.url = url
        self.maxPixelSize = maxPixelSize
        self.placeholderFont = placeholderFont
    }

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "waveform")
                    .font(placeholderFont)
                    .foregroundStyle(palette.textSecondary)
            }
        }
        .background(palette.surfaceElevated)
        .accessibilityHidden(true)
        .task(id: ArtworkCacheKey(url: url, maxPixelSize: maxPixelSize)) {
            image = nil
            guard let url else { return }
            let result = await withCooperativeTimeout(
                .seconds(2),
                owner: timeoutTaskOwner
            ) {
                await ArtworkThumbnailDecoder.thumbnail(
                    at: url,
                    maxPixelSize: maxPixelSize
                )
            }
            guard !Task.isCancelled, case .value(let thumbnail) = result else { return }
            image = thumbnail?.image
        }
        .onDisappear {
            timeoutTaskOwner.cancelAll()
        }
    }
}

private final class ArtworkThumbnailBox: @unchecked Sendable {
    let image: NSImage
    init(_ image: NSImage) { self.image = image }
}

private final class ArtworkThumbnailCache: @unchecked Sendable {
    static let shared = ArtworkThumbnailCache()
    let images = NSCache<NSString, ArtworkThumbnailBox>()

    private init() { images.countLimit = 300 }
}

private enum ArtworkThumbnailDecoder {
    nonisolated static func thumbnail(
        at url: URL,
        maxPixelSize: Int
    ) async -> ArtworkThumbnailBox? {
        guard !Task.isCancelled else { return nil }
        let key = ArtworkCacheKey(url: url, maxPixelSize: maxPixelSize).cacheKey as NSString
        if let cached = ArtworkThumbnailCache.shared.images.object(forKey: key) { return cached }
        guard
            let image = await ArtworkImageDecoder.thumbnail(
                at: url,
                maxPixelSize: maxPixelSize
            )
        else { return nil }
        let thumbnail = ArtworkThumbnailBox(
            NSImage(
                cgImage: image,
                size: NSSize(width: image.width, height: image.height)
            )
        )
        guard !Task.isCancelled else { return nil }
        ArtworkThumbnailCache.shared.images.setObject(thumbnail, forKey: key)
        return thumbnail
    }
}

private struct ArtworkCacheKey: Hashable {
    let url: URL?
    let maxPixelSize: Int

    var cacheKey: String {
        "\(url?.absoluteString ?? "placeholder")#\(maxPixelSize)"
    }
}
