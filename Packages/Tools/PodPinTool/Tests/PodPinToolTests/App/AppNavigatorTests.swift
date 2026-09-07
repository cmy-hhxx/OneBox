import XCTest

@testable import PodPinTool

@MainActor
final class AppNavigatorTests: XCTestCase {
    func testCompletingCurrentImportReturnsToLibrary() throws {
        let navigator = AppNavigator()
        navigator.openImport()
        let context = try XCTUnwrap(navigator.importContext)

        navigator.completeImport(context)

        XCTAssertEqual(navigator.routeStack, [.library])
    }

    func testCompletingImportPreservesNowPlayingAndQueue() throws {
        let navigator = AppNavigator()
        navigator.openImport()
        let context = try XCTUnwrap(navigator.importContext)
        navigator.showQueue()
        let routes = navigator.routeStack

        navigator.completeImport(context)

        XCTAssertEqual(navigator.routeStack, routes)
        XCTAssertTrue(navigator.isQueuePresented)
    }

    func testCompletingPreviousImportPreservesNewImportDraft() throws {
        let navigator = AppNavigator()
        navigator.openImport()
        let oldContext = try XCTUnwrap(navigator.importContext)
        navigator.showLibraryContent()
        navigator.openImport()
        navigator.importDraft.shareText = "new draft"
        let routes = navigator.routeStack

        navigator.completeImport(oldContext)

        XCTAssertEqual(navigator.routeStack, routes)
        XCTAssertEqual(navigator.importDraft.shareText, "new draft")
    }

    func testWorkspaceDestinationsStayInsideTheToolContent() {
        let navigator = AppNavigator()

        navigator.openImport()
        guard case .importLink(let context) = navigator.currentRoute else {
            return XCTFail("Expected import destination")
        }
        XCTAssertEqual(context.destinationFolderID, LibraryFolder.inboxID)
        XCTAssertEqual(navigator.routeStack.count, 2)

        navigator.showLibraryContent()
        XCTAssertEqual(navigator.routeStack, [.library])
    }

    func testOpeningImportCarriesTheSelectedFolderContext() {
        let navigator = AppNavigator()
        let folderID = UUID()

        navigator.openImport(in: folderID)

        guard case .importLink(let context) = navigator.currentRoute else {
            return XCTFail("Expected import destination")
        }
        XCTAssertEqual(context.destinationFolderID, folderID)
        XCTAssertEqual(context.defaultNewFolderParentID, folderID)
        XCTAssertEqual(navigator.routeDirection, .push)
    }

    func testOpeningTheCurrentImportDestinationDoesNotPushOrReplaceItsContext() {
        let navigator = AppNavigator()
        navigator.openImport(in: UUID())
        let originalRoutes = navigator.routeStack

        navigator.openImport(in: UUID())

        XCTAssertEqual(navigator.routeStack, originalRoutes)
    }

    func testOpeningImportFromNowPlayingReturnsToExistingImportWithoutNewDraft() {
        let navigator = AppNavigator()
        let folderID = UUID()
        navigator.openImport(in: folderID)
        navigator.showNowPlaying()

        let shouldCreateDraft = navigator.openImport(in: UUID())

        XCTAssertFalse(shouldCreateDraft)
        XCTAssertEqual(navigator.routeStack.count, 2)
        guard case .importLink(let context) = navigator.currentRoute else {
            return XCTFail("Expected the existing import destination")
        }
        XCTAssertEqual(context.destinationFolderID, folderID)
        XCTAssertEqual(navigator.routeDirection, .pop)
    }

    func testOpeningImportFromNowPlayingAtLibraryCreatesANewImportRoute() {
        let navigator = AppNavigator()
        let folderID = UUID()
        navigator.showNowPlaying()

        let shouldCreateDraft = navigator.openImport(in: folderID)

        XCTAssertTrue(shouldCreateDraft)
        XCTAssertEqual(navigator.routeStack.count, 2)
        guard case .importLink(let context) = navigator.currentRoute else {
            return XCTFail("Expected a new import destination")
        }
        XCTAssertEqual(context.destinationFolderID, folderID)
        XCTAssertEqual(navigator.routeDirection, .push)
    }

    func testInboxImportCreatesFoldersAtTheLibraryRootByDefault() {
        let context = ImportEntryContext(destinationFolderID: LibraryFolder.inboxID)
        XCTAssertNil(context.defaultNewFolderParentID)
    }

    func testNowPlayingReturnsToThePreviousWorkspaceDestination() {
        let navigator = AppNavigator()
        navigator.openImport()
        let importContext = navigator.importContext

        navigator.showNowPlaying()
        XCTAssertEqual(navigator.currentRoute, .nowPlaying)
        XCTAssertEqual(navigator.routeStack.count, 3)
        XCTAssertEqual(navigator.importContext, importContext)

        navigator.closeNowPlaying()
        guard case .importLink = navigator.currentRoute else {
            return XCTFail("Expected the previous import destination")
        }
        XCTAssertEqual(navigator.importContext, importContext)
        XCTAssertEqual(navigator.routeDirection, .pop)
    }

    func testImportDraftSurvivesPushingAndPoppingNowPlaying() {
        let navigator = AppNavigator()
        let destinationFolderID = UUID()
        navigator.openImport(in: destinationFolderID)
        navigator.importDraft.shareText = "https://example.com/audio"
        navigator.importDraft.selectedContentIDs = ["segment-2"]

        navigator.showNowPlaying()
        navigator.closeNowPlaying()

        XCTAssertEqual(navigator.importDraft.shareText, "https://example.com/audio")
        XCTAssertEqual(navigator.importDraft.selectedContentIDs, ["segment-2"])
        XCTAssertEqual(navigator.importDraft.destinationFolderID, destinationFolderID)
    }

    func testNewImportRouteResetsTheRootOwnedDraft() {
        let navigator = AppNavigator()
        navigator.openImport(in: UUID())
        navigator.importDraft.shareText = "https://example.com/old"
        navigator.showLibraryContent()
        let newDestinationFolderID = UUID()

        navigator.openImport(in: newDestinationFolderID)

        XCTAssertEqual(navigator.importDraft.shareText, "")
        XCTAssertTrue(navigator.importDraft.selectedContentIDs.isEmpty)
        XCTAssertEqual(navigator.importDraft.destinationFolderID, newDestinationFolderID)
    }

    func testNowPlayingCannotBePushedTwice() {
        let navigator = AppNavigator()
        navigator.showNowPlaying()
        navigator.showNowPlaying()

        XCTAssertEqual(navigator.routeStack, [.library, .nowPlaying])
    }

    func testShowingLibraryClearsEveryPushedRoute() {
        let navigator = AppNavigator()
        navigator.openImport(in: UUID())
        navigator.showNowPlaying()

        navigator.showLibraryContent()

        XCTAssertEqual(navigator.routeStack, [.library])
        XCTAssertNil(navigator.importContext)
    }

    func testShowingQueuePushesNowPlayingAndPresentsItsInspector() {
        let navigator = AppNavigator()

        navigator.showQueue()

        XCTAssertEqual(navigator.currentRoute, .nowPlaying)
        XCTAssertTrue(navigator.isQueuePresented)

        navigator.closeNowPlaying()

        XCTAssertEqual(navigator.currentRoute, .library)
        XCTAssertFalse(navigator.isQueuePresented)
    }

    func testExitCommandDismissesQueueBeforeNowPlayingAndThenStopsAtLibrary() {
        let navigator = AppNavigator()
        navigator.showQueue(reduceMotion: true)

        XCTAssertTrue(navigator.handleExitCommand(reduceMotion: true))
        XCTAssertFalse(navigator.isQueuePresented)
        XCTAssertEqual(navigator.currentRoute, .nowPlaying)

        XCTAssertTrue(navigator.handleExitCommand(reduceMotion: true))
        XCTAssertEqual(navigator.currentRoute, .library)

        XCTAssertFalse(navigator.handleExitCommand(reduceMotion: true))
        XCTAssertEqual(navigator.currentRoute, .library)
    }

    func testExitCommandPopsImportToLibrary() {
        let navigator = AppNavigator()
        navigator.openImport(reduceMotion: true)

        XCTAssertTrue(navigator.handleExitCommand(reduceMotion: true))
        XCTAssertEqual(navigator.currentRoute, .library)
    }
}
