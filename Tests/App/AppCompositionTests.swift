import XCTest

@testable import OneBox

final class AppCompositionTests: XCTestCase {
    @MainActor
    func testCompositionRegistersExpectedToolsInSidebarOrder() {
        let registrations = AppComposition.makeCatalog().registrations

        XCTAssertEqual(
            registrations.map(\.id.rawValue),
            [
                "ascii-art",
                "stock-watch",
                "blog-listen",
                "window-focus",
            ]
        )
    }

    func testStockWatchAlertSoundsAndThirdPartyNoticesAreBundled() {
        XCTAssertNotNil(Bundle.main.url(forResource: "bull-moo", withExtension: "wav"))
        XCTAssertNotNil(Bundle.main.url(forResource: "bear-growl", withExtension: "wav"))
        XCTAssertNotNil(
            Bundle.main.url(forResource: "THIRD_PARTY_NOTICES", withExtension: "md")
        )
    }
}
