import SwiftUI

@MainActor
final class AppNavigator: ObservableObject {
    @Published var destination: LibraryDestination = .library

    private var nowPlayingReturnDestination: LibraryDestination?

    func openImport(in folderID: UUID = LibraryFolder.inboxID) {
        nowPlayingReturnDestination = nil
        destination = .importLink(ImportEntryContext(destinationFolderID: folderID))
    }

    func showLibraryContent() {
        nowPlayingReturnDestination = nil
        destination = .library
    }

    func showNowPlaying() {
        guard destination != .nowPlaying else { return }
        nowPlayingReturnDestination = destination
        destination = .nowPlaying
    }

    func closeNowPlaying() {
        guard case .nowPlaying = destination else { return }
        destination = nowPlayingReturnDestination ?? .library
        nowPlayingReturnDestination = nil
    }
}
