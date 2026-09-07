import Foundation

/// Adapts persisted folders into the UI tree without doing repeated ancestor
/// walks. The async entry point keeps this CPU-only work off the main actor.
nonisolated enum LibraryFolderTreeBuilder {
    @concurrent
    static func build(from folders: [LibraryFolder]) async throws -> [LibraryFolderNode] {
        try Task.checkCancellation()
        let tree = buildSynchronously(from: folders)
        try Task.checkCancellation()
        return tree
    }

    /// Exposed internally so deterministic benchmarks can time the exact
    /// production algorithm without introducing task-scheduling noise.
    static func buildSynchronously(from folders: [LibraryFolder]) -> [LibraryFolderNode] {
        guard !folders.isEmpty else { return [] }

        let foldersByID = Dictionary(uniqueKeysWithValues: folders.map { ($0.id, $0) })
        let childrenByParent = Dictionary(grouping: folders, by: \.parentID)
        let rootIDs = (childrenByParent[nil] ?? []).map(\.id)

        struct Frame {
            let folderID: UUID
            let buildsNode: Bool
        }

        var nodesByID: [UUID: LibraryFolderNode] = [:]
        nodesByID.reserveCapacity(folders.count)
        var visited: Set<UUID> = []
        visited.reserveCapacity(folders.count)

        for rootID in rootIDs {
            var stack = [Frame(folderID: rootID, buildsNode: false)]

            while let frame = stack.popLast() {
                guard let folder = foldersByID[frame.folderID] else { continue }

                if frame.buildsNode {
                    let children = (childrenByParent[folder.id] ?? []).compactMap {
                        nodesByID.removeValue(forKey: $0.id)
                    }
                    nodesByID[folder.id] = LibraryFolderNode(
                        id: folder.id,
                        folderID: folder.id,
                        name: folder.displayName,
                        isSystemFolder: folder.isSystemFolder,
                        children: children
                    )
                    continue
                }

                guard visited.insert(folder.id).inserted else { continue }
                stack.append(Frame(folderID: folder.id, buildsNode: true))
                for child in (childrenByParent[folder.id] ?? []).reversed() {
                    stack.append(Frame(folderID: child.id, buildsNode: false))
                }
            }
        }

        return rootIDs.compactMap { nodesByID.removeValue(forKey: $0) }
    }
}
