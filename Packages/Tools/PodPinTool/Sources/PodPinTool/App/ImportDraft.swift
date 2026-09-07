import Foundation

/// User-authored import state lives above the route content so pushing the
/// player never discards an in-progress import.
struct ImportDraft {
    var shareText = ""
    var preview: ImportDiscovery?
    var selectedContentIDs = Set<String>()
    var destinationFolderID: UUID

    init(destinationFolderID: UUID) {
        self.destinationFolderID = destinationFolderID
    }
}
