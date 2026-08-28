import Foundation

/// Filesystem companion to the SQLite library. The database keeps only paths
/// relative to this root, so moving the entire PodPin support folder remains
/// predictable and a corrupt database can never point outside user data.
struct PodPinMediaStore: @unchecked Sendable {
    static let mediaDirectoryName = "Media"

    let rootURL: URL
    private let fileManager: FileManager

    init(rootURL: URL, fileManager: FileManager = .default) throws {
        self.rootURL = rootURL.standardizedFileURL
        self.fileManager = fileManager
        try fileManager.createDirectory(at: self.rootURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(
            at: mediaRootURL,
            withIntermediateDirectories: true
        )
    }

    static func inApplicationSupport(fileManager: FileManager = .default) throws -> PodPinMediaStore
    {
        return try PodPinMediaStore(
            rootURL: PodPinLibraryLocation.rootURL(fileManager: fileManager),
            fileManager: fileManager
        )
    }

    var mediaRootURL: URL {
        rootURL.appendingPathComponent(Self.mediaDirectoryName, isDirectory: true)
    }

    func directory(for itemID: UUID) -> URL {
        mediaRootURL.appendingPathComponent(itemID.uuidString.lowercased(), isDirectory: true)
    }

    func relativeAudioPath(for itemID: UUID) -> String {
        "\(Self.mediaDirectoryName)/\(itemID.uuidString.lowercased())/audio.m4a"
    }

    func relativeArtworkPath(for itemID: UUID) -> String {
        "\(Self.mediaDirectoryName)/\(itemID.uuidString.lowercased())/artwork"
    }

    /// Keeps a thumbnail outside an item's directory until the database still
    /// confirms that the item exists. This prevents a late network response
    /// from recreating media for an item that was deleted meanwhile.
    func temporaryArtworkURL(for itemID: UUID) -> URL {
        mediaRootURL.appendingPathComponent(
            ".artwork-\(itemID.uuidString.lowercased())-\(UUID().uuidString.lowercased()).tmp"
        )
    }

    func absoluteURL(for relativePath: String) throws -> URL {
        let candidate = rootURL.appendingPathComponent(relativePath).standardizedFileURL
        guard candidate.path.hasPrefix(rootURL.path + "/") else {
            throw MarketDatabaseError.invalidRelativePath
        }
        return candidate
    }

    nonisolated func removeMedia(for itemID: UUID) async throws {
        let directory = directory(for: itemID)
        guard fileManager.fileExists(atPath: directory.path) else { return }
        try fileManager.removeItem(at: directory)
    }

    nonisolated func removeDownloadedAudio(for itemID: UUID) async throws {
        let directory = directory(for: itemID)
        guard fileManager.fileExists(atPath: directory.path) else { return }
        let contents = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        for url in contents
        where url.lastPathComponent == "audio.m4a"
            || url.lastPathComponent.hasPrefix(".download-")
        {
            try fileManager.removeItem(at: url)
        }
    }

    nonisolated func resetMediaDirectory(for itemID: UUID) async throws -> URL {
        let directory = directory(for: itemID)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try await removeDownloadedAudio(for: itemID)
        return directory
    }

    nonisolated func installArtwork(at temporaryURL: URL, for itemID: UUID) async throws {
        let destination = try absoluteURL(for: relativeArtworkPath(for: itemID))
        try fileManager.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.moveItem(at: temporaryURL, to: destination)
    }

    nonisolated func removeTemporaryArtwork(at temporaryURL: URL) async {
        // This is best-effort cleanup after a successful artwork transaction;
        // callers retain the original import error if cleanup itself fails.
        try? fileManager.removeItem(at: temporaryURL)
    }

    nonisolated func containsFile(at relativePath: String) async -> Bool {
        guard let url = try? absoluteURL(for: relativePath) else { return false }
        return fileManager.fileExists(atPath: url.path)
    }
}
