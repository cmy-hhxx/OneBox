import Foundation

/// A user-visible collection in the local library. Smart collections are
/// derived from persisted item metadata; folders retain their existing
/// user-defined organisation.
enum LibraryCollection: Hashable, Codable, Sendable {
    case recentlyImported
    case recentlyPlayed
    case downloaded
    case folder(UUID)

    var defaultImportFolderID: UUID {
        if case .folder(let id) = self {
            return id
        }
        return LibraryFolder.inboxID
    }

    var title: String {
        switch self {
        case .recentlyImported: "最近导入"
        case .recentlyPlayed: "最近播放"
        case .downloaded: "已下载"
        case .folder: "资料库"
        }
    }
}
