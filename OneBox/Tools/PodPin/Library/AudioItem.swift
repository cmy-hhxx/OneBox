import Foundation

/// The source family that owns a stable content identifier.
public enum AudioPlatform: String, Codable, CaseIterable, Sendable {
    case fixture
    case bilibili
    case douyin
    case fireside
    case xiaoyuzhou
}

/// Whether playback resolves a temporary remote stream or reads a file from PodPin's media store.
public enum AudioStorageKind: String, Codable, CaseIterable, Sendable {
    case online
    case offline
}

/// The lifecycle of an offline download. Online items always use `.notRequested`.
public enum AudioDownloadState: String, Codable, CaseIterable, Sendable {
    case notRequested = "not_requested"
    case downloading
    case available
    case failed
}

/// A single playable audio entry in the local library.
public struct AudioItem: Identifiable, Codable, Equatable, Hashable, Sendable {
    public let id: UUID
    public var platform: AudioPlatform
    public var contentID: String
    public var sourceURL: URL
    public var title: String
    public var author: String?
    public var artworkRelativePath: String?
    public var duration: TimeInterval?
    /// Every audio item belongs to a concrete library destination. Historical
    /// unfiled rows are migrated into the system inbox before they are decoded.
    public var folderID: UUID
    public var storageKind: AudioStorageKind
    public var downloadState: AudioDownloadState
    public var localMediaRelativePath: String?
    public var playbackPosition: TimeInterval
    public var listeningHistory: ListeningHistory
    public var lastPlayedAt: Date?
    public let importedAt: Date
    public var updatedAt: Date

    public init(
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
