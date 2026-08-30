import AppKit
import CoreGraphics
import Foundation
import XCTest

@testable import PodPinTool

private final class ArtworkGeneratorProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var completion: (@Sendable (CGImage?) -> Void)?
    private var cancelCount = 0
    let submitted = XCTestExpectation(description: "thumbnail request submitted")

    func generator() -> ArtworkThumbnailGenerator {
        ArtworkThumbnailGenerator(
            generate: { [weak self] _, completion in
                self?.lock.lock()
                self?.completion = completion
                self?.lock.unlock()
                self?.submitted.fulfill()
            },
            cancel: { [weak self] _ in
                self?.lock.lock()
                self?.cancelCount += 1
                self?.lock.unlock()
            }
        )
    }

    func completeLate(with image: CGImage?) {
        lock.lock()
        let completion = completion
        lock.unlock()
        completion?(image)
    }

    func recordedCancelCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return cancelCount
    }
}

final class ArtworkImageDecoderTests: XCTestCase {
    func testCooperativeTimeoutCancelsAndDrainsOperation() async {
        let result = await withCooperativeTimeout(.milliseconds(20)) {
            do {
                try await Task.sleep(for: .seconds(3_600))
                return 1
            } catch {
                return 2
            }
        }

        guard case .timedOut = result else {
            return XCTFail("Expected timeout to win")
        }
    }

    func testCancellationStopsWaitingAndRejectsLateGeneratorResult() async {
        let probe = ArtworkGeneratorProbe()
        let task = Task {
            await ArtworkImageDecoder.thumbnail(
                at: URL(fileURLWithPath: "/tmp/extensionless-artwork"),
                maxPixelSize: 48,
                generator: probe.generator()
            )
        }
        await fulfillment(of: [probe.submitted], timeout: 1)

        task.cancel()
        let result = await task.value

        XCTAssertNil(result)
        XCTAssertGreaterThanOrEqual(probe.recordedCancelCount(), 1)
        probe.completeLate(with: makeCGImage())
    }

    func testTimeoutCancelsGeneratorRequestAndDrainsDecoder() async {
        let probe = ArtworkGeneratorProbe()
        let result = await withCooperativeTimeout(.milliseconds(20)) {
            await ArtworkImageDecoder.thumbnail(
                at: URL(fileURLWithPath: "/tmp/extensionless-artwork"),
                maxPixelSize: 48,
                generator: probe.generator()
            )
        }

        guard case .timedOut = result else {
            return XCTFail("Expected generator request to time out")
        }
        XCTAssertGreaterThanOrEqual(probe.recordedCancelCount(), 1)
    }

    func testQuickLookThumbnailDecoderReturnsBoundedImage() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "ArtworkImageDecoderTests-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let imageURL = root.appendingPathComponent("artwork")
        try makePNGData().write(to: imageURL, options: .atomic)

        let result = await withCooperativeTimeout(.seconds(2)) {
            await ArtworkImageDecoder.thumbnail(at: imageURL, maxPixelSize: 48)
        }

        guard case .value(let image?) = result else {
            return XCTFail("Expected a Quick Look thumbnail")
        }
        XCTAssertLessThanOrEqual(image.width, 48)
        XCTAssertLessThanOrEqual(image.height, 48)
    }

    private func makeCGImage() -> CGImage {
        let context = CGContext(
            data: nil,
            width: 96,
            height: 96,
            bitsPerComponent: 8,
            bytesPerRow: 96 * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(NSColor.systemBlue.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 96, height: 96))
        return context.makeImage()!
    }

    private func makePNGData() throws -> Data {
        let bitmap = NSBitmapImageRep(cgImage: makeCGImage())
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return data
    }
}
