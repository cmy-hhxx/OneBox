import Darwin
import Metal
import XCTest
import os

@testable import AsciiArtTool

final class AsciiPerformanceTests: XCTestCase {
    @MainActor
    func testFullHDStaticExportMeetsReleaseBudget() async throws {
        #if DEBUG
            throw XCTSkip("Run this benchmark with scripts/benchmark-ascii.sh")
        #else
            var settings = AsciiSettings()
            settings.canvasPreset = .landscape
            let image = try OneBoxSourceImage.make()
            let source = AsciiSource(image: image)
            let snapshot = AsciiRenderSnapshot(
                settings: settings,
                transform: CanvasTransform(),
                sourceSize: CGSize(width: image.width, height: image.height)
            )
            let cache = AsciiRenderCache(
                deviceProvider: TestAsciiMetalDeviceProvider()
            )
            let pipeline = try await cache.preparedPipeline()
            _ = try await AsciiPNGExporter.renderPrepared(
                pipeline: pipeline,
                source: source,
                snapshot: snapshot
            )
            var durations: [TimeInterval] = []
            let options = XCTMeasureOptions()
            options.iterationCount = 30

            measure(metrics: [XCTClockMetric(), XCTMemoryMetric()], options: options) {
                let startedAt = ProcessInfo.processInfo.systemUptime
                waitForAsyncOperation {
                    _ = try await AsciiPNGExporter.renderPrepared(
                        pipeline: pipeline,
                        source: source,
                        snapshot: snapshot
                    )
                }
                durations.append(ProcessInfo.processInfo.systemUptime - startedAt)
            }

            XCTAssertLessThanOrEqual(durations.max() ?? .infinity, 2)
            XCTAssertLessThanOrEqual(try currentPhysicalFootprint(), 250 * 1024 * 1024)
        #endif
    }

    private func waitForAsyncOperation(
        _ operation: @escaping @Sendable () async throws -> Void
    ) {
        let semaphore = DispatchSemaphore(value: 0)
        let result = OSAllocatedUnfairLock<Result<Void, Error>?>(initialState: nil)
        Task.detached {
            do {
                try await operation()
                result.withLock { $0 = .success(()) }
            } catch {
                result.withLock { $0 = .failure(error) }
            }
            semaphore.signal()
        }
        XCTAssertEqual(semaphore.wait(timeout: .now() + 10), .success)
        XCTAssertNoThrow(try result.withLock { try $0?.get() })
    }

    private func currentPhysicalFootprint() throws -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPointer in
                task_info(
                    mach_task_self_,
                    task_flavor_t(TASK_VM_INFO),
                    reboundPointer,
                    &count
                )
            }
        }
        guard result == KERN_SUCCESS else {
            throw AsciiToolError.exportFailed
        }
        return info.phys_footprint
    }
}
