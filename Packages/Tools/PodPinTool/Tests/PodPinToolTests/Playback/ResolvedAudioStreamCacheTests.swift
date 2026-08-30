import Foundation
import XCTest

@testable import PodPinTool

final class ResolvedAudioStreamCacheTests: XCTestCase {
    func testReturnsCachedStreamUntilItsTimeToLiveExpires() async {
        let clock = MutableTestClock()
        let cache = ResolvedAudioStreamCache(
            capacity: 8,
            timeToLive: 5 * 60,
            now: { clock.value() }
        )
        let item = makeItem(contentID: "cache-hit")
        let stream = makeStream(path: "first")

        await cache.insert(stream, for: item)

        let cachedStream = await cache.stream(for: item)
        XCTAssertEqual(cachedStream, stream)

        clock.advance(by: 5 * 60 + 1)
        let expiredStream = await cache.stream(for: item)
        XCTAssertNil(expiredStream)
    }

    func testInvalidatingAnItemRemovesItsCachedStreamAfterPlaybackFailure() async {
        let cache = ResolvedAudioStreamCache()
        let item = makeItem(contentID: "failure")
        let stream = makeStream(path: "failure")

        await cache.insert(stream, for: item)
        await cache.invalidate(itemID: item.id)

        let cachedStream = await cache.stream(for: item)
        XCTAssertNil(cachedStream)
    }

    func testEvictsLeastRecentlyUsedEntryWhenAtCapacity() async {
        let clock = MutableTestClock()
        let cache = ResolvedAudioStreamCache(capacity: 2, now: { clock.value() })
        let first = makeItem(contentID: "first")
        let second = makeItem(contentID: "second")
        let third = makeItem(contentID: "third")

        await cache.insert(makeStream(path: "first"), for: first)
        clock.advance(by: 1)
        await cache.insert(makeStream(path: "second"), for: second)
        clock.advance(by: 1)
        _ = await cache.stream(for: first)
        clock.advance(by: 1)
        await cache.insert(makeStream(path: "third"), for: third)

        let firstCachedStream = await cache.stream(for: first)
        let secondCachedStream = await cache.stream(for: second)
        let thirdCachedStream = await cache.stream(for: third)
        XCTAssertNotNil(firstCachedStream)
        XCTAssertNil(secondCachedStream)
        XCTAssertNotNil(thirdCachedStream)
    }

    private func makeItem(contentID: String) -> AudioItem {
        AudioItem(
            platform: .fixture,
            contentID: contentID,
            sourceURL: URL(string: "https://example.invalid/\(contentID)")!,
            title: contentID
        )
    }

    private func makeStream(path: String) -> ResolvedAudioStream {
        ResolvedAudioStream(
            url: URL(string: "https://media.example.invalid/\(path).m4a")!,
            headers: ["Referer": "https://example.invalid"],
            duration: 60
        )
    }
}

private final class MutableTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var now = Date(timeIntervalSinceReferenceDate: 0)

    func value() -> Date {
        lock.lock()
        defer { lock.unlock() }
        return now
    }

    func advance(by interval: TimeInterval) {
        lock.lock()
        now.addTimeInterval(interval)
        lock.unlock()
    }
}
