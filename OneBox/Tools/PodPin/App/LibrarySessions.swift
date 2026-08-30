import Combine
import Foundation

/// Low-frequency library state. Its small interface gives the workspace a
/// single snapshot to observe while database and import work stay elsewhere.
@MainActor
final class LibrarySession: ObservableObject {
    @Published var folders: [LibraryFolder] = []
    @Published var selectedCollection: LibraryCollection = .recentlyImported
    @Published var items: [AudioItem] = []
    @Published var startupError: String?
    @Published var startupPhase: LibraryStartupPhase = .loading
    @Published var itemsPhase: LibraryItemsPhase = .idle
    @Published var isStarting = false
    @Published var canLoadMoreItems = false
}

/// Import-only presentation state. Parsing, verification, and browser profile
/// changes no longer publish through the playback and library state object.
@MainActor
final class ImportSession: ObservableObject {
    @Published var verificationRequest: PlatformVerificationRequest?
    @Published var browserProfiles: [BrowserProfile] = []
    @Published var hasRequestedBrowserProfiles = false
    @Published var isDiscoveringBrowserProfiles = false
    @Published var issue: PresentedError?
}

/// Download queue state. Keeping high-frequency progress in this dedicated
/// object lets only the active progress renderer refresh during a transfer.
@MainActor
final class DownloadSession: ObservableObject {
    @Published var activeItemID: UUID?
    @Published private(set) var snapshot = DownloadProgressSnapshot.indeterminate

    var progress: Double? { snapshot.fraction }
    var bytesPerSecond: Double? { snapshot.bytesPerSecond }

    func update(_ snapshot: DownloadProgressSnapshot) {
        self.snapshot = snapshot
    }

    func reset() {
        snapshot = .indeterminate
    }
}
