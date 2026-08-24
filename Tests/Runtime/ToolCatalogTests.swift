import SwiftUI
import XCTest
@testable import OneBoxRuntime

final class ToolCatalogTests: XCTestCase {
    @MainActor
    func testRegistrationLookupReturnsMatchingTool() {
        let registration = ToolRegistration(
            id: ToolID(rawValue: "test-tool"),
            displayName: "Test Tool"
        ) { _ in
            Text("Test")
        }
        let catalog = ToolCatalog(registrations: [registration])

        XCTAssertEqual(catalog.registration(for: registration.id)?.id, registration.id)
    }

    @MainActor
    func testRegistrationLookupReturnsNilWithoutSelection() {
        let catalog = ToolCatalog(registrations: [])

        XCTAssertNil(catalog.registration(for: nil))
    }
}
