import XCTest

@testable import PodPinTool

@MainActor
final class AppNavigatorTests: XCTestCase {
    func testWorkspaceDestinationsStayInsideTheToolContent() {
        let navigator = AppNavigator()

        navigator.openImport()
        guard case .importLink(let context) = navigator.destination else {
            return XCTFail("Expected import destination")
        }
        XCTAssertEqual(context.destinationFolderID, LibraryFolder.inboxID)

        navigator.showLibraryContent()
        XCTAssertEqual(navigator.destination, .library)
    }

    func testOpeningImportCarriesTheSelectedFolderContext() {
        let navigator = AppNavigator()
        let folderID = UUID()

        navigator.openImport(in: folderID)

        guard case .importLink(let context) = navigator.destination else {
            return XCTFail("Expected import destination")
        }
        XCTAssertEqual(context.destinationFolderID, folderID)
        XCTAssertEqual(context.defaultNewFolderParentID, folderID)
    }

    func testInboxImportCreatesFoldersAtTheLibraryRootByDefault() {
        let context = ImportEntryContext(destinationFolderID: LibraryFolder.inboxID)
        XCTAssertNil(context.defaultNewFolderParentID)
    }

    func testNowPlayingReturnsToThePreviousWorkspaceDestination() {
        let navigator = AppNavigator()
        navigator.openImport()

        navigator.showNowPlaying()
        XCTAssertEqual(navigator.destination, .nowPlaying)

        navigator.closeNowPlaying()
        guard case .importLink = navigator.destination else {
            return XCTFail("Expected the previous import destination")
        }
    }

    func testSettingsPresentationKeepsTheCurrentWorkspaceRoute() {
        let navigator = AppNavigator()
        let folderID = UUID()
        navigator.openImport(in: folderID)

        navigator.showSettings()

        XCTAssertTrue(navigator.isSettingsPresented)
        guard case .importLink(let context) = navigator.destination else {
            return XCTFail("Settings must not replace the current workspace")
        }
        XCTAssertEqual(context.destinationFolderID, folderID)

        navigator.closeSettings()
        XCTAssertFalse(navigator.isSettingsPresented)
        guard case .importLink = navigator.destination else {
            return XCTFail("Closing settings must preserve the current workspace")
        }
    }
}
