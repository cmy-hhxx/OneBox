import Testing

@testable import AsciiArtTool

@MainActor
@Suite("ASCII async deadlines")
struct AsciiAsyncDeadlineTests {
    @Test
    func `operation finishing before deadline returns its value`() async throws {
        let value = try await AsciiAsyncDeadline.run(for: .seconds(1)) {
            42
        }

        #expect(value == 42)
    }

    @Test
    func `operation exceeding deadline throws timeout`() async throws {
        do {
            _ = try await AsciiAsyncDeadline.run(for: .milliseconds(10)) {
                try await Task.sleep(for: .seconds(1))
                return 42
            }
            Issue.record("Slow operation unexpectedly completed before its deadline")
        } catch is AsciiTimeoutError {
            // Expected typed deadline failure.
        }
    }
}
