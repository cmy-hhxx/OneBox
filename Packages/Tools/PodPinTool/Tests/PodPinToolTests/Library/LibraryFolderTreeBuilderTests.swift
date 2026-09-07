import XCTest

@testable import PodPinTool

final class LibraryFolderTreeBuilderTests: XCTestCase {
    func testBuildPreservesRootAndSiblingOrder() {
        let root = folder("Root")
        let first = folder("First", parentID: root.id)
        let second = folder("Second", parentID: root.id)
        let leaf = folder("Leaf", parentID: first.id)

        let tree = LibraryFolderTreeBuilder.buildSynchronously(
            from: [root, first, second, leaf]
        )

        XCTAssertEqual(tree.map(\.id), [root.id])
        XCTAssertEqual(tree[0].children.map(\.id), [first.id, second.id])
        XCTAssertEqual(tree[0].children[0].children.map(\.id), [leaf.id])
        XCTAssertEqual(tree[0].children[0].folderID, first.id)
    }

    func testBuildOmitsOrphansAndCyclesThatCannotReachARoot() {
        let missingParentID = UUID()
        let orphan = folder("Orphan", parentID: missingParentID)
        let firstCycleID = UUID()
        let secondCycleID = UUID()
        let firstCycle = LibraryFolder(
            id: firstCycleID,
            parentID: secondCycleID,
            name: "Cycle A"
        )
        let secondCycle = LibraryFolder(
            id: secondCycleID,
            parentID: firstCycleID,
            name: "Cycle B"
        )

        XCTAssertTrue(
            LibraryFolderTreeBuilder.buildSynchronously(
                from: [orphan, firstCycle, secondCycle]
            ).isEmpty
        )
    }

    private func folder(_ name: String, parentID: UUID? = nil) -> LibraryFolder {
        LibraryFolder(parentID: parentID, name: name)
    }
}
