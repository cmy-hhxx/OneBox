import Foundation
import XCTest

@testable import PodPinTool

final class AudioItemTests: XCTestCase {
    func testOnlineItemDefaultsToTheInboxAndNoDownload() {
        let item = AudioItem(
            platform: .fixture,
            contentID: "welcome",
            sourceURL: URL(string: "https://fixture.podpin.local/welcome")!,
            title: "Welcome"
        )

        XCTAssertEqual(item.folderID, LibraryFolder.inboxID)
        XCTAssertEqual(item.storageKind, .online)
        XCTAssertEqual(item.downloadState, .notRequested)
        XCTAssertNil(item.localMediaRelativePath)
        XCTAssertEqual(item.playbackPosition, 0)
    }

    func testInboxHasAStableSystemIdentity() {
        XCTAssertEqual(LibraryFolder.inbox.id, LibraryFolder.inboxID)
        XCTAssertTrue(LibraryFolder.inbox.isSystemFolder)
        XCTAssertNil(LibraryFolder.inbox.parentID)
    }
}
