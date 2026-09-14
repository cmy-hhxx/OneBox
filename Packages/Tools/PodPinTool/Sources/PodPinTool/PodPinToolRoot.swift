import Foundation
import OneBoxRuntime
import SwiftUI

/// Startup opens persistence off the main actor. The `@Sendable` factories use
/// this wrapper to carry the injected, thread-safe `FileManager` reference.
final class PodPinFileManagerReference: @unchecked Sendable {
    let value: FileManager

    init(_ value: FileManager) {
        self.value = value
    }
}

@MainActor
struct PodPinToolRoot: View {
    private let lifecycle: PodPinToolLifecycle
    @ObservedObject private var store: PodPinStore
    @ObservedObject private var librarySession: LibrarySession
    @Environment(\.toolContentReadinessReporter) private var contentReadinessReporter

    init(session: PodPinModuleSession) {
        let lifecycle = session.contentLifecycle()
        self.lifecycle = lifecycle
        _store = ObservedObject(wrappedValue: lifecycle.store)
        _librarySession = ObservedObject(wrappedValue: lifecycle.store.librarySession)
        lifecycle.store.beginWarmResumePresentation()
    }

    var body: some View {
        PodPinLibraryView()
            .environmentObject(store)
            .environmentObject(lifecycle.navigator)
            .task {
                await lifecycle.store.resumeUI()
            }
            .onDisappear {
                // Visibility is paired with the actual surface lifecycle. A
                // cancelled startup task may finish after a newer surface has
                // appeared, so task-tail cleanup must not suspend that surface.
                lifecycle.store.suspendUI()
            }
            .onAppear {
                store.finishWarmResumePresentation()
            }
            .onChange(of: firstContentResolved, initial: true) { _, isResolved in
                guard isResolved else { return }
                contentReadinessReporter.reportFirstContentReady()
            }
    }

    private var firstContentResolved: Bool {
        switch librarySession.startupPhase {
        case .loading:
            false
        case .ready, .failed:
            true
        }
    }
}

@MainActor
final class PodPinToolLifecycle {
    let store: PodPinStore
    let navigator = AppNavigator()

    init(
        platform: any PodPinPlatformProviding,
        debugFixtureAudioURL: URL?,
        externalToolsDirectoryURL: URL?,
        applicationSupportDirectoryURL: URL? = nil,
        allowsNetworkAccess: Bool = true,
        diagnostics: ToolDiagnostics = .disabled
    ) {
        let fileManager = platform.fileManager
        let fileManagerReference = PodPinFileManagerReference(fileManager)
        let libraryRootURL = applicationSupportDirectoryURL?.appendingPathComponent(
            MarketDatabase.applicationSupportFolderName,
            isDirectory: true
        )
        let fixture = debugFixtureAudioURL.map(FixtureContentImporter.init(audioURL:))
        let toolLocator = BundledToolLocator(
            toolsDirectoryURL: externalToolsDirectoryURL
        )
        store = PodPinStore(
            preferences: AppPreferences(defaults: platform.legacyPreferences),
            databaseFactory: {
                if let libraryRootURL {
                    try fileManagerReference.value.createDirectory(
                        at: libraryRootURL,
                        withIntermediateDirectories: true
                    )
                    return try MarketDatabase.open(
                        at: libraryRootURL.appendingPathComponent(
                            MarketDatabase.defaultFileName,
                            isDirectory: false
                        )
                    )
                }
                return try MarketDatabase.openInApplicationSupport(
                    fileManager: fileManagerReference.value
                )
            },
            mediaStoreFactory: {
                if let libraryRootURL {
                    return try PodPinMediaStore(
                        rootURL: libraryRootURL,
                        fileManager: fileManagerReference.value
                    )
                }
                return try PodPinMediaStore.inApplicationSupport(
                    fileManager: fileManagerReference.value
                )
            },
            importer: PodPinContentImporter(
                fixture: fixture,
                fixtureFailure: fixture == nil
                    ? .mediaUnavailable("示例音频没有随应用安装。")
                    : nil,
                toolLocator: toolLocator,
                sourceAdapters: allowsNetworkAccess ? nil : []
            ),
            browserAccessAuthorizer: BrowserAccessBroker(
                reference: fileManagerReference,
                applicationSupportURL: applicationSupportDirectoryURL
            ),
            playbackController: AudioPlaybackController(
                playerFactory: platform.makeAudioPlayer, diagnostics: diagnostics
            ),
            nowPlayingController: NowPlayingController(
                commandCenter: platform.remoteCommandCenter,
                nowPlayingInfoCenter: platform.nowPlayingInfoCenter
            ),
            diagnostics: diagnostics
        )
    }
}
