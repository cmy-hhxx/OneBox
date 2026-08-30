import Foundation

/// Resolves the one directory shared by the database and media store.
enum PodPinLibraryLocation {
    static func rootURL(fileManager: FileManager = .default) throws -> URL {
        guard
            let applicationSupport = fileManager.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first
        else {
            throw MarketDatabaseError.applicationSupportUnavailable
        }
        let root = applicationSupport.appendingPathComponent(
            MarketDatabase.applicationSupportFolderName,
            isDirectory: true
        )
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}
