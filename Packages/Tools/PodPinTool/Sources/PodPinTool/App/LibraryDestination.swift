import Foundation

/// Carries the folder context into a newly opened import workspace. A fresh ID
/// also gives SwiftUI a stable way to discard stale parse state when the user
/// opens import again from a different folder.
struct ImportEntryContext: Hashable, Identifiable, Sendable {
    let id: UUID
    let destinationFolderID: UUID

    init(id: UUID = UUID(), destinationFolderID: UUID) {
        self.id = id
        self.destinationFolderID = destinationFolderID
    }

    var defaultNewFolderParentID: UUID? {
        destinationFolderID == LibraryFolder.inboxID ? nil : destinationFolderID
    }
}

/// The library window owns every long-lived workspace. Folder selection stays
/// in the store; this route only decides which workspace occupies the detail
/// pane.
enum LibraryDestination: Hashable, Sendable {
    case library
    case importLink(ImportEntryContext)
    case nowPlaying
}
