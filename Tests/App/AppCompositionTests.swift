import XCTest
@testable import OneBox

final class AppCompositionTests: XCTestCase {
    @MainActor
    func testCompositionRegistersExpectedToolsInSidebarOrder() {
        let registrations = AppComposition.makeCatalog().registrations

        XCTAssertEqual(
            registrations.map(\.id.rawValue),
            [
                "stock-watch",
                "blog-listen",
                "window-focus",
            ]
        )
    }

}
