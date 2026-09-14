import AppKit
import OneBoxDesignSystem
import SwiftUI
import XCTest

@testable import PodPinTool

@MainActor
final class PodPinVisualValidationTests: XCTestCase {
    func testResponsiveWorkspaceReferenceRendersProduceInspectablePNGs() async throws {
        let database = try MarketDatabase.inMemory()
        let mediaRoot = FileManager.default.temporaryDirectory.appendingPathComponent(
            "OneBox-PodPin-Visual-\(UUID().uuidString)", isDirectory: true
        )
        let suiteName = "OneBox.PodPinVisualValidation.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: mediaRoot)
        }
        let samples = try await seed(database)
        let store = PodPinStore(
            preferences: AppPreferences(defaults: defaults),
            databaseFactory: { database },
            mediaStoreFactory: { try PodPinMediaStore(rootURL: mediaRoot) },
            importer: try FixtureContentImporter.testFixture()
        )
        let navigator = AppNavigator()
        await store.start()
        XCTAssertEqual(store.items.count, samples.count)

        do {
            for size in [CGSize(width: 716, height: 510), CGSize(width: 616, height: 418)] {
                let suffix = size.width == 716 ? "default" : "minimum"
                navigator.showLibraryContent(reduceMotion: true)
                store.playbackPresentation.update(.empty)
                store.playbackQueue.session.replaceEntries([])
                store.selectedCollection = .recentlyImported
                try await settle()
                try await capture(
                    "podpin-library-\(suffix)", size: size, store: store, navigator: navigator)

                navigator.openImport(reduceMotion: true)
                try await capture(
                    "podpin-import-\(suffix)", size: size, store: store, navigator: navigator)

                store.playbackPresentation.update(
                    PlaybackSnapshot(
                        item: samples[0], phase: .paused, currentTime: 487,
                        duration: samples[0].duration ?? 0, rate: 1.25
                    )
                )
                store.playbackQueue.session.replaceEntries(
                    samples.dropFirst().enumerated().map { index, item in
                        PlaybackQueueEntry(item: item, position: index, enqueuedAt: item.importedAt)
                    }
                )
                navigator.showNowPlaying(reduceMotion: true)
                try await capture(
                    "podpin-player-\(suffix)", size: size, store: store, navigator: navigator)

                navigator.showQueue(reduceMotion: true)
                try await capture(
                    "podpin-queue-\(suffix)", size: size, store: store, navigator: navigator)

                try await captureQueuePanel(
                    "podpin-queue-content-\(suffix)", height: size.height, store: store)

                navigator.showLibraryContent(reduceMotion: true)
                store.selectedCollection = .downloaded
                try await settle()
                XCTAssertTrue(store.items.isEmpty)
                try await capture(
                    "podpin-empty-\(suffix)", size: size, store: store, navigator: navigator)
            }
            let folderEditor = FolderEditorSheet(
                request: FolderEditorRequest(operation: .create, source: .sidebar),
                folderTree: store.folderTree(),
                onSave: { _, _, _ in }
            )
            .font(DesignTypography.body)
            .background(DesignPalette.light.surface)
            .tint(DesignPalette.light.accent)
            .frame(width: 420, height: 400)
            try await render(
                "podpin-folder-editor", size: CGSize(width: 420, height: 400), root: folderEditor)
        } catch {
            await store.shutdown()
            throw error
        }
        await store.shutdown()
    }

    private func capture(
        _ name: String,
        size: CGSize,
        store: PodPinStore,
        navigator: AppNavigator
    ) async throws {
        let root = PodPinLibraryView()
            .environmentObject(store)
            .environmentObject(navigator)
            .environment(\.oneBoxAccessibilityReduceMotionOverride, true)
            .tint(DesignPalette.light.accent)
            .transaction { $0.disablesAnimations = true }
            .frame(width: size.width, height: size.height)
        try await render(name, size: size, root: root)
    }

    private func captureQueuePanel(_ name: String, height: CGFloat, store: PodPinStore) async throws
    {
        let root = ScrollView {
            NowPlayingQueueView(
                session: store.playbackQueue.session,
                artworkURL: { _ in nil },
                onPlay: { _ in },
                onRemove: { _ in },
                onMove: { _, _ in },
                onClear: {},
                onRetry: {}
            )
            .padding(DesignMetrics.space16)
        }
        .background(DesignPalette.light.surface)
        .tint(DesignPalette.light.accent)
        .frame(width: 320, height: height)
        try await render(name, size: CGSize(width: 320, height: height), root: root)
    }

    private func render<Content: View>(_ name: String, size: CGSize, root: Content) async throws {
        let host = NSHostingView(
            rootView: root.environment(\.oneBoxAccessibilityReduceMotionOverride, true))
        host.appearance = NSAppearance(named: .aqua)
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(
            contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false
        )
        window.contentView = host
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        window.orderFrontRegardless()
        defer {
            window.orderOut(nil)
            window.contentView = nil
        }
        try await settle()
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        XCTAssertGreaterThan(png.count, 10_000)
        let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let directory = ProcessInfo.processInfo.environment["ONEBOX_UI_SNAPSHOT_DIRECTORY"] {
            let url = URL(fileURLWithPath: directory, isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            try png.write(to: url.appendingPathComponent("\(name).png"))
        }
    }

    private func settle() async throws {
        await Task.yield()
        try await Task.sleep(for: .milliseconds(100))
    }

    private func seed(_ database: MarketDatabase) async throws -> [AudioItem] {
        let titles = [
            "城市声音漫游：在日常里，重新发现值得倾听的细节",
            "EP. 42 一场关于阅读、创造与好奇心的对谈",
            "把时间留给音乐：秋日夜晚的聆听笔记",
        ]
        let authors = ["声音散步", "日常研究所", "慢电台"]
        var items: [AudioItem] = []
        for (index, title) in titles.enumerated() {
            items.append(
                try await database.insertItem(
                    AudioItem(
                        platform: .xiaoyuzhou,
                        contentID: "visual-\(index)",
                        sourceURL: try XCTUnwrap(
                            URL(string: "https://example.invalid/audio/\(index)")),
                        title: title,
                        author: authors[index],
                        duration: 2_460 + Double(index * 720),
                        playbackPosition: index == 0 ? 487 : 0,
                        importedAt: Date(
                            timeIntervalSince1970: 1_784_000_000 - Double(index * 600)),
                        updatedAt: Date(timeIntervalSince1970: 1_784_000_000)
                    )
                )
            )
        }
        return items
    }
}
