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

/// A typed route retained in order so a pushed player can reveal the exact
/// workspace beneath it when it is popped.
enum PodPinRoute: Hashable, Identifiable, Sendable {
    enum ID: Hashable, Sendable {
        case library
        case importLink(UUID)
        case nowPlaying
    }

    case library
    case importLink(ImportEntryContext)
    case nowPlaying

    var id: ID {
        switch self {
        case .library: .library
        case .importLink(let context): .importLink(context.id)
        case .nowPlaying: .nowPlaying
        }
    }
}
