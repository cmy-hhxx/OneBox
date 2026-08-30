import Foundation

/// The source family that owns a stable content identifier.
enum AudioPlatform: String, Codable, CaseIterable, Sendable {
    case fixture
    case bilibili
    case douyin
    case fireside
    case xiaoyuzhou
}

/// Whether playback resolves a temporary remote stream or reads a file from PodPin's media store.
enum AudioStorageKind: String, Codable, CaseIterable, Sendable {
    case online
    case offline
}

/// The lifecycle of an offline download. Online items always use `.notRequested`.
enum AudioDownloadState: String, Codable, CaseIterable, Sendable {
    case notRequested = "not_requested"
    case downloading
    case available
    case failed
}

/// A single playable audio entry in the local library.
struct AudioItem: Identifiable, Codable, Equatable, Hashable, Sendable {
    let id: UUID
    var platform: AudioPlatform
    var contentID: String
    var sourceURL: URL
    var title: String
    var author: String?
    var artworkRelativePath: String?
    var duration: TimeInterval?
    /// Every audio item belongs to a concrete library destination. Historical
    /// unfiled rows are migrated into the system inbox before they are decoded.
    var folderID: UUID
    var storageKind: AudioStorageKind
    var downloadState: AudioDownloadState
    var localMediaRelativePath: String?
    var playbackPosition: TimeInterval
    var listeningHistory: ListeningHistory
    var lastPlayedAt: Date?
    let importedAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        platform: AudioPlatform,
        contentID: String,
        sourceURL: URL,
        title: String,
        author: String? = nil,
        artworkRelativePath: String? = nil,
        duration: TimeInterval? = nil,
        folderID: UUID = LibraryFolder.inboxID,
        storageKind: AudioStorageKind = .online,
        downloadState: AudioDownloadState = .notRequested,
        localMediaRelativePath: String? = nil,
        playbackPosition: TimeInterval = 0,
        listeningHistory: ListeningHistory = ListeningHistory(),
        lastPlayedAt: Date? = nil,
        importedAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.platform = platform
        self.contentID = contentID
        self.sourceURL = sourceURL
        self.title = title
        self.author = author
        self.artworkRelativePath = artworkRelativePath
        self.duration = duration
        self.folderID = folderID
        self.storageKind = storageKind
        self.downloadState = downloadState
        self.localMediaRelativePath = localMediaRelativePath
        self.playbackPosition = playbackPosition
        self.listeningHistory = listeningHistory
        self.lastPlayedAt = lastPlayedAt
        self.importedAt = importedAt
        self.updatedAt = updatedAt
    }
}
