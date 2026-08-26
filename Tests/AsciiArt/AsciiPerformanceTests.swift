import Darwin
import Metal
import XCTest

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
            let source = AsciiSource(image: image, name: "OneBox", isBuiltIn: true)
            let snapshot = AsciiRenderSnapshot(
                settings: settings,
                transform: CanvasTransform(),
                sourceSize: CGSize(width: image.width, height: image.height)
            )
            let cache = AsciiRenderCache(
                deviceProvider: TestAsciiMetalDeviceProvider()
            )
            _ = try await cache.preparedPipeline()

            let clock = ContinuousClock()
            let start = clock.now
            _ = try await AsciiPNGExporter.render(
                cache: cache,
                source: source,
                snapshot: snapshot
            )
            let elapsed = start.duration(to: clock.now)

            XCTAssertLessThanOrEqual(elapsed, .seconds(2))
            XCTAssertLessThanOrEqual(try currentPhysicalFootprint(), 250 * 1024 * 1024)
        #endif
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
