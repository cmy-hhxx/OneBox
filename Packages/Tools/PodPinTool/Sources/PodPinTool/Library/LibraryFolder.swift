import Foundation

/// Distinguishes the folders owned by the user from the built-in inbox.
enum LibraryFolderSystemKind: String, Codable, CaseIterable, Sendable {
    case user
    case inbox
}

/// A node in the audio library's folder tree.
struct LibraryFolder: Identifiable, Codable, Equatable, Hashable, Sendable {
    /// A stable identifier lets the database recreate the inbox on every fresh library.
    static let inboxID = UUID(uuidString: "E312B35F-32CB-4BA3-9EAF-706FF1B0184B")!

    let id: UUID
    var parentID: UUID?
    var name: String
    let systemKind: LibraryFolderSystemKind
    let createdAt: Date

    init(
        id: UUID = UUID(),
        parentID: UUID? = nil,
        name: String,
        systemKind: LibraryFolderSystemKind = .user,
        createdAt: Date = .now
    ) {
        self.id = id
        self.parentID = parentID
        self.name = name
        self.systemKind = systemKind
        self.createdAt = createdAt
    }

    static let inbox = LibraryFolder(
        id: inboxID,
        name: "收件箱",
        systemKind: .inbox,
        createdAt: Date(timeIntervalSince1970: 0)
    )

    var isSystemFolder: Bool {
        systemKind != .user
    }

    /// System folders own their localized presentation name so a legacy
    /// database label (for example, "Inbox") can never leak into the UI.
    var displayName: String {
        switch systemKind {
        case .inbox:
            "收件箱"
        case .user:
            name
        }
    }
}
