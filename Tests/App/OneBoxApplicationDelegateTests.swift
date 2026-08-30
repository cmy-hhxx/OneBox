import AppKit
import XCTest

@testable import OneBox

final class OneBoxApplicationDelegateTests: XCTestCase {
    @MainActor
    func testTerminationCoordinatorPreparesOnceThenRepliesWithoutBlocking() async {
        var events: [String] = []
        let replyReceived = expectation(description: "Termination reply received")
        let coordinator = ApplicationTerminationCoordinator()
        coordinator.configure {
            events.append("prepare-start")
            await Task.yield()
            events.append("prepare-end")
        }

        let firstReply = coordinator.applicationShouldTerminate { shouldTerminate in
            events.append("reply-\(shouldTerminate)")
            replyReceived.fulfill()
        }
        let repeatedReply = coordinator.applicationShouldTerminate { shouldTerminate in
            events.append("repeated-reply-\(shouldTerminate)")
        }

        XCTAssertEqual(firstReply, .terminateLater)
        XCTAssertEqual(repeatedReply, .terminateLater)
        XCTAssertEqual(events, [])

        await fulfillment(of: [replyReceived], timeout: 1)

        XCTAssertEqual(events, ["prepare-start", "prepare-end", "reply-true"])
    }

    @MainActor
    func testTerminationTimeoutCancelsPreparationAndReplies() async {
        let replyReceived = expectation(description: "Termination reply received")
        let preparationCancelled = expectation(description: "Preparation cancelled")
        let coordinator = ApplicationTerminationCoordinator(timeout: .milliseconds(50))
        coordinator.configure {
            do {
                try await Task.sleep(for: .seconds(30))
            } catch {
                preparationCancelled.fulfill()
            }
        }

        let result = coordinator.applicationShouldTerminate { shouldTerminate in
            XCTAssertTrue(shouldTerminate)
            replyReceived.fulfill()
        }

        XCTAssertEqual(result, .terminateLater)
        await fulfillment(of: [replyReceived, preparationCancelled], timeout: 1)
    }

}
