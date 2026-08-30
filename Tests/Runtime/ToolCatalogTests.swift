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
    func testCatalogStartsAllPreparationsBeforeWaitingForCompletion() async throws {
        let firstGate = CatalogPreparationGate()
        let secondGate = CatalogPreparationGate()
        let first = ToolRegistration(
            id: ToolID(rawValue: "first"),
            displayName: "First",
            onApplicationTermination: {
                await firstGate.run()
            },
            content: {
                Text("First")
            }
        )
        let second = ToolRegistration(
            id: ToolID(rawValue: "second"),
            displayName: "Second",
            onApplicationTermination: {
                await secondGate.run()
            },
            content: {
                Text("Second")
            }
        )
        let catalog = ToolCatalog(registrations: [first, second])
        var preparationFinished = false
        let preparation = Task { @MainActor in
            await catalog.prepareForApplicationTermination()
            preparationFinished = true
        }

        try await firstGate.waitUntilStarted()
        try await secondGate.waitUntilStarted()
        XCTAssertFalse(preparationFinished)

        await firstGate.finish()
        for _ in 0..<10 {
            await Task.yield()
        }
        XCTAssertFalse(preparationFinished)

        await secondGate.finish()
        await preparation.value
        XCTAssertTrue(preparationFinished)
    }

    @MainActor
    func testCancellingCatalogPreparationCancelsEveryToolPreparation() async throws {
        let firstGate = CatalogPreparationGate()
        let secondGate = CatalogPreparationGate()
        let registrations = [
            ToolRegistration(
                id: ToolID(rawValue: "first"),
                displayName: "First",
                onApplicationTermination: { await firstGate.run() },
                content: { Text("First") }
            ),
            ToolRegistration(
                id: ToolID(rawValue: "second"),
                displayName: "Second",
                onApplicationTermination: { await secondGate.run() },
                content: { Text("Second") }
            ),
        ]
        let preparation = Task { @MainActor in
            await ToolCatalog(registrations: registrations)
                .prepareForApplicationTermination()
        }
        try await firstGate.waitUntilStarted()
        try await secondGate.waitUntilStarted()

        preparation.cancel()

        try await firstGate.waitUntilCancelled()
        try await secondGate.waitUntilCancelled()
        await firstGate.finish()
        await secondGate.finish()
        await preparation.value
    }
}

private enum CatalogPreparationGateError: Error {
    case didNotStart
    case wasNotCancelled
}

private actor CatalogPreparationGate {
    private var started = false
    private var cancelled = false
    private var finished = false

    func run() async {
        started = true
        while !finished {
            if Task.isCancelled {
                cancelled = true
            }
            await Task.yield()
        }
    }

    func waitUntilStarted() async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(1))
        while !started, clock.now < deadline {
            await Task.yield()
        }
        guard started else { throw CatalogPreparationGateError.didNotStart }
    }

    func waitUntilCancelled() async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(1))
        while !cancelled, clock.now < deadline {
            await Task.yield()
        }
        guard cancelled else { throw CatalogPreparationGateError.wasNotCancelled }
    }

    func finish() {
        finished = true
    }
}
