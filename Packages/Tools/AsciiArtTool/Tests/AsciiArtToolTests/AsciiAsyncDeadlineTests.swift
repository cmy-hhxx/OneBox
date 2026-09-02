import Testing

@testable import AsciiArtTool

@MainActor
@Suite("ASCII async deadlines")
struct AsciiAsyncDeadlineTests {
    @Test
    func `operation finishing before deadline returns its value`() async throws {
        let owner = AsciiAsyncWorkOwner()
        let value = try await AsciiAsyncDeadline.run(for: .seconds(1), owner: owner) {
            42
        }

        #expect(value == 42)
        await owner.cancelAndWait()
    }

    @Test
    func `operation exceeding deadline throws timeout`() async throws {
        let owner = AsciiAsyncWorkOwner()
        do {
            _ = try await AsciiAsyncDeadline.run(for: .milliseconds(10), owner: owner) {
                try await Task.sleep(for: .seconds(1))
                return 42
            }
            Issue.record("Slow operation unexpectedly completed before its deadline")
        } catch is AsciiTimeoutError {
            // Expected typed deadline failure.
        }
        await owner.cancelAndWait()
    }

    @Test
    func `deadline does not await a noncooperative operation`() async throws {
        let gate = AsciiNonCooperativeOperationGate()
        let owner = AsciiAsyncWorkOwner()
        let clock = ContinuousClock()
        let startedAt = clock.now

        do {
            _ = try await AsciiAsyncDeadline.run(for: .milliseconds(20), owner: owner) {
                await gate.wait()
                return 42
            }
            Issue.record("Blocked operation unexpectedly completed")
        } catch is AsciiTimeoutError {
            #expect(startedAt.duration(to: clock.now) < .milliseconds(200))
        }
        #expect(owner.activeTaskCount == 1)
        await gate.release()
        await owner.cancelAndWait()
        #expect(owner.activeTaskCount == 0)
    }
}

private actor AsciiNonCooperativeOperationGate {
    private var isReleased = false
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        guard !isReleased else { return }
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func release() {
        isReleased = true
        continuation?.resume()
        continuation = nil
    }
}
