import SwiftUI
import XCTest

@testable import OneBoxRuntime

final class ToolCatalogTests: XCTestCase {
    @MainActor
    func testRegistrationLookupReturnsMatchingTool() {
        let registration = ToolRegistration(
            id: ToolID(rawValue: "test-tool"),
            displayName: "Test Tool"
        ) {
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

    @MainActor
    func testContentFactoryRunsLazily() {
        var constructionCount = 0
        let registration = ToolRegistration(
            id: ToolID(rawValue: "test-tool"),
            displayName: "Test Tool"
        ) {
            constructionCount += 1
            return Text("Test")
        }

        XCTAssertEqual(constructionCount, 0)

        _ = registration.content()

        XCTAssertEqual(constructionCount, 1)
    }

    @MainActor
    func testTerminationPreparationRunsLazily() async {
        var preparationCount = 0
        let registration = ToolRegistration(
            id: ToolID(rawValue: "test-tool"),
            displayName: "Test Tool",
            onApplicationTermination: {
                preparationCount += 1
            },
            content: {
                Text("Test")
            }
        )

        XCTAssertEqual(preparationCount, 0)

        await registration.prepareForApplicationTermination()

        XCTAssertEqual(preparationCount, 1)
    }

    @MainActor
    func testCatalogPreparesEachRegistrationOnceInRegistrationOrder() async {
        var calls: [String] = []
        let first = ToolRegistration(
            id: ToolID(rawValue: "first"),
            displayName: "First",
            onApplicationTermination: {
                calls.append("first-start")
                await Task.yield()
                calls.append("first-end")
            },
            content: {
                Text("First")
            }
        )
        let second = ToolRegistration(
            id: ToolID(rawValue: "second"),
            displayName: "Second",
            onApplicationTermination: {
                calls.append("second")
            },
            content: {
                Text("Second")
            }
        )
        let catalog = ToolCatalog(registrations: [first, second])

        await catalog.prepareForApplicationTermination()

        XCTAssertEqual(calls, ["first-start", "first-end", "second"])
    }
}
