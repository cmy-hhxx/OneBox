import XCTest

@testable import PodPinTool

final class LibraryFolderOutlineTests: XCTestCase {
    func testInitialExpansionIncludesRootsWithoutASelection() {
        let firstRoot = node("First", children: [node("Collapsed")])
        let secondRoot = node("Second")

        let expanded = LibraryFolderOutline.initiallyExpandedFolderIDs(
            in: [firstRoot, secondRoot],
            selectedFolderID: nil
        )

        XCTAssertEqual(expanded, Set([firstRoot.id, secondRoot.id]))
    }

    func testInitialExpansionContainsOnlyTheSelectedPath() {
        let leaf = node("Leaf")
        let selected = node("Selected", children: [leaf])
        let sibling = node("Sibling", children: [node("Hidden")])
        let root = node("Root", children: [selected, sibling])

        let expanded = LibraryFolderOutline.initiallyExpandedFolderIDs(
            in: [root],
            selectedFolderID: leaf.id
        )

        XCTAssertEqual(expanded, Set([root.id, selected.id, leaf.id]))
        XCTAssertFalse(expanded.contains(sibling.id))
    }

    func testVisibleRowsOnlyDescendIntoExpandedFolders() {
        let visibleLeaf = node("Visible")
        let hiddenLeaf = node("Hidden")
        let expandedBranch = node("Expanded", children: [visibleLeaf])
        let collapsedBranch = node("Collapsed", children: [hiddenLeaf])

        let rows = LibraryFolderOutline.visibleRows(
            in: [expandedBranch, collapsedBranch],
            expandedFolderIDs: [expandedBranch.id],
            excluding: []
        )

        XCTAssertEqual(rows.map(\.id), [expandedBranch.id, visibleLeaf.id, collapsedBranch.id])
        XCTAssertEqual(rows.map(\.depth), [0, 1, 0])
    }

    func testExcludedFolderIsOmittedWithoutAddingIndentation() {
        let child = node("Child")
        let excluded = node("Excluded", children: [child])

        let rows = LibraryFolderOutline.visibleRows(
            in: [excluded],
            expandedFolderIDs: [],
            excluding: [excluded.id]
        )

        XCTAssertEqual(rows.map(\.id), [child.id])
        XCTAssertEqual(rows.map(\.depth), [0])
    }

    private func node(
        _ name: String,
        children: [LibraryFolderNode] = []
    ) -> LibraryFolderNode {
        LibraryFolderNode(id: UUID(), name: name, children: children)
    }
}
