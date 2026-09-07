import Foundation

struct LibraryFolderOutlineRow: Identifiable {
    let folder: LibraryFolderNode
    let depth: Int

    var id: UUID { folder.id }
    var hasChildren: Bool { !folder.children.isEmpty }
}

enum LibraryFolderOutline {
    static func initiallyExpandedFolderIDs(
        in folders: [LibraryFolderNode],
        selectedFolderID: UUID?
    ) -> Set<UUID> {
        var expanded = Set(folders.map(\.id))
        guard let selectedFolderID,
            let path = path(to: selectedFolderID, in: folders)
        else { return expanded }

        expanded.formUnion(path)
        return expanded
    }

    static func visibleRows(
        in folders: [LibraryFolderNode],
        expandedFolderIDs: Set<UUID>,
        excluding excludedFolderIDs: Set<UUID>
    ) -> [LibraryFolderOutlineRow] {
        var rows: [LibraryFolderOutlineRow] = []
        var stack = folders.reversed().map { (folder: $0, depth: 0) }

        while let entry = stack.popLast() {
            let folder = entry.folder
            if excludedFolderIDs.contains(folder.id) {
                for child in folder.children.reversed() {
                    stack.append((folder: child, depth: entry.depth))
                }
                continue
            }

            rows.append(LibraryFolderOutlineRow(folder: folder, depth: entry.depth))
            guard expandedFolderIDs.contains(folder.id) else { continue }
            for child in folder.children.reversed() {
                stack.append((folder: child, depth: entry.depth + 1))
            }
        }
        return rows
    }

    static func path(
        to folderID: UUID,
        in folders: [LibraryFolderNode]
    ) -> [UUID]? {
        var parentByFolderID: [UUID: UUID] = [:]
        var stack = folders.reversed().map { (folder: $0, parentID: Optional<UUID>.none) }

        while let entry = stack.popLast() {
            if let parentID = entry.parentID {
                parentByFolderID[entry.folder.id] = parentID
            }
            if entry.folder.id == folderID {
                var reversedPath = [folderID]
                var currentID = folderID
                while let parentID = parentByFolderID[currentID] {
                    reversedPath.append(parentID)
                    currentID = parentID
                }
                return reversedPath.reversed()
            }
            for child in entry.folder.children.reversed() {
                stack.append((folder: child, parentID: entry.folder.id))
            }
        }
        return nil
    }

    static func allFolderIDs(in folders: [LibraryFolderNode]) -> Set<UUID> {
        var result: Set<UUID> = []
        var stack = Array(folders.reversed())
        while let folder = stack.popLast() {
            result.insert(folder.id)
            stack.append(contentsOf: folder.children.reversed())
        }
        return result
    }
}
