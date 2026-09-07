import AppKit
import Darwin
import XCTest

final class OneBoxPerformanceUITests: XCTestCase {
    private struct ProcessUsageSnapshot {
        let physicalFootprint: UInt64
        let userTime: UInt64
        let systemTime: UInt64
        let bytesRead: UInt64
        let bytesWritten: UInt64
    }

    private struct FileSnapshot: Equatable {
        let relativePath: String
        let size: Int
        let modificationDate: Date?
    }

    private var dataRootURLs: [URL] = []

    override func setUpWithError() throws {
        continueAfterFailure = false
        guard ProcessInfo.processInfo.environment["ONEBOX_RUN_PERFORMANCE_TESTS"] == "1" else {
            throw XCTSkip("Run with the OneBoxPerformance test plan.")
        }
    }

    override func tearDownWithError() throws {
        for dataRootURL in dataRootURLs.reversed() {
            OneBoxUITestSupport.cleanUp(dataRootURL: dataRootURL)
        }
        dataRootURLs = []
    }

    @MainActor
    func testColdLaunchToInteractiveWorkspace() throws {
        let application = XCUIApplication()
        defer { application.terminate() }
        var launchToInteractionDurations: [TimeInterval] = []
        let metrics: [any XCTMetric] = [
            XCTApplicationLaunchMetric(waitUntilResponsive: true),
            signpostMetric(category: "Host", name: "AppLaunchToInteractive"),
            signpostMetric(category: "Host", name: "InspectorPresentation"),
        ]

        measure(metrics: metrics, options: measureOptions(iterationCount: 10)) {
            do {
                _ = try makeConfiguredDataRoot(
                    for: application,
                    prefix: "OneBox-LaunchPerformance"
                )
            } catch {
                XCTFail("Could not prepare isolated launch fixture: \(error)")
                return
            }

            let startedAt = ContinuousClock.now
            application.launch()
            XCTAssertTrue(mainReadyMarker(in: application).waitForExistence(timeout: 2))

            let inspectorToggle = application.buttons["ascii.inspector-toggle"]
            let inspectorClose = application.buttons["关闭参数"]
            XCTAssertTrue(inspectorToggle.waitForExistence(timeout: 1))
            XCTAssertTrue(inspectorToggle.isHittable)

            let duration = startedAt.duration(to: ContinuousClock.now)
            launchToInteractionDurations.append(seconds(in: duration))

            XCTAssertFalse(inspectorClose.exists)
            inspectorToggle.click()
            XCTAssertTrue(inspectorClose.waitForExistence(timeout: 1))
            inspectorToggle.click()
            XCTAssertTrue(inspectorClose.waitForNonExistence(timeout: 1))
            application.terminate()
        }

        // XCTest invokes one extra warmup iteration before the measured samples.
        let sortedDurations = launchToInteractionDurations.dropFirst().sorted()
        guard sortedDurations.count == 10 else {
            XCTFail("Expected 10 cold-launch samples, got \(sortedDurations.count)")
            return
        }
        let upperMiddleIndex = sortedDurations.count / 2
        let median = (sortedDurations[upperMiddleIndex - 1] + sortedDurations[upperMiddleIndex]) / 2
        XCTAssertLessThanOrEqual(median, 1.0, "Cold launch median exceeded 1.0 second")
        XCTAssertLessThanOrEqual(
            sortedDurations.last ?? .infinity,
            1.5,
            "Cold launch maximum exceeded 1.5 seconds"
        )
    }

    @MainActor
    func testWarmToolActivationAndSwitching() throws {
        let application = try launchIsolatedApplication(prefix: "OneBox-WarmSwitchPerformance")
        defer { application.terminate() }
        warmAllTools(in: application)
        var stockWatchDurations: [TimeInterval] = []
        var podPinDurations: [TimeInterval] = []
        var asciiDurations: [TimeInterval] = []

        measure(
            metrics: [
                signpostMetric(category: "Host", name: "ToolActivation"),
                signpostMetric(category: "Host", name: "FirstContentReady"),
                XCTMemoryMetric(application: application),
            ],
            options: measureOptions(iterationCount: 30)
        ) {
            stockWatchDurations.append(
                measureToolSelection(
                    "股票看盘",
                    readyElement: application.buttons["添加标的"],
                    in: application
                )
            )
            podPinDurations.append(
                measureToolSelection(
                    "PodPin",
                    readyElement: podPinReadyContent(in: application),
                    in: application
                )
            )
            asciiDurations.append(
                measureToolSelection(
                    "ASCII 工坊",
                    readyElement: application.descendants(matching: .any)["ascii.workspace"],
                    in: application
                )
            )
        }

        assertLatencyBudget(
            "Warm switch to StockWatch",
            samples: stockWatchDurations,
            expectedCount: 30,
            p95Limit: 0.2
        )
        assertLatencyBudget(
            "Warm switch to PodPin",
            samples: podPinDurations,
            expectedCount: 30,
            p95Limit: 0.2
        )
        assertLatencyBudget(
            "Warm switch to ASCII",
            samples: asciiDurations,
            expectedCount: 30,
            p95Limit: 0.2
        )
    }

    @MainActor
    func testPodPinWarmReentry() throws {
        let application = try launchIsolatedApplication(prefix: "OneBox-PodPinWarmReentry")
        defer { application.terminate() }
        showPodPinLibrary(in: application)
        showASCII(in: application)
        var warmReentryDurations: [TimeInterval] = []

        measure(
            metrics: [
                signpostMetric(category: "PodPin", name: "PodPinWarmResume"),
                XCTMemoryMetric(application: application),
            ],
            options: measureOptions(iterationCount: 30)
        ) {
            warmReentryDurations.append(
                measureToolSelection(
                    "PodPin",
                    readyElement: podPinReadyContent(in: application),
                    in: application
                )
            )
            showASCII(in: application)
        }

        assertLatencyBudget(
            "PodPin warm reentry to retained content",
            samples: warmReentryDurations,
            expectedCount: 30,
            p95Limit: 0.1
        )
    }

    @MainActor
    func testInspectorAndPodPinRoutePresentation() throws {
        let application = try launchIsolatedApplication(prefix: "OneBox-PresentationPerformance")
        defer { application.terminate() }
        warmAllTools(in: application)
        var asciiInspectorDurations: [TimeInterval] = []
        var stockWatchInspectorDurations: [TimeInterval] = []
        var queueInspectorDurations: [TimeInterval] = []
        var libraryToImportDurations: [TimeInterval] = []
        var importToNowPlayingDurations: [TimeInterval] = []
        var nowPlayingToImportDurations: [TimeInterval] = []
        var importToLibraryDurations: [TimeInterval] = []

        measure(
            metrics: [
                signpostMetric(category: "Host", name: "InspectorPresentation"),
                signpostMetric(category: "PodPin", name: "RoutePush"),
                signpostMetric(category: "PodPin", name: "RoutePop"),
                XCTMemoryMetric(application: application),
            ],
            options: measureOptions(iterationCount: 30)
        ) {
            let asciiInspectorToggle = application.buttons["ascii.inspector-toggle"]
            let asciiInspectorClose = application.buttons["关闭参数"]
            asciiInspectorDurations.append(
                measureVisibleResponse(
                    triggeredBy: asciiInspectorToggle,
                    visibleElement: asciiInspectorClose
                )
            )
            application.typeKey(.escape, modifierFlags: [])
            XCTAssertTrue(asciiInspectorClose.waitForNonExistence(timeout: 1))

            showStockWatch(in: application)
            let showStockInspector = application.buttons["显示检查器"]
            XCTAssertTrue(showStockInspector.waitForExistence(timeout: 1))
            let stockWatchInspectorClose = application.buttons["关闭检查器"]
            stockWatchInspectorDurations.append(
                measureVisibleResponse(
                    triggeredBy: showStockInspector,
                    visibleElement: stockWatchInspectorClose
                )
            )
            application.typeKey(.escape, modifierFlags: [])
            XCTAssertTrue(showStockInspector.waitForExistence(timeout: 1))

            showPodPinLibrary(in: application)
            let importButton = application.buttons["workspace.import"]
            let importInput = application.textViews["import.link-input"]
            libraryToImportDurations.append(
                measureVisibleResponse(
                    triggeredBy: importButton,
                    visibleElement: importInput
                )
            )
            let nowPlayingButton = application.buttons["workspace.now-playing"]
            let player = application.otherElements["now-playing.player"]
            importToNowPlayingDurations.append(
                measureVisibleResponse(
                    triggeredBy: nowPlayingButton,
                    visibleElement: player
                )
            )

            let queueToggle = application.buttons["now-playing.queue-toggle"]
            let queue = application.otherElements["now-playing.queue"]
            queueInspectorDurations.append(
                measureVisibleResponse(
                    triggeredBy: queueToggle,
                    visibleElement: queue
                )
            )
            queueToggle.click()
            XCTAssertTrue(queue.waitForNonExistence(timeout: 1))

            nowPlayingToImportDurations.append(
                measureVisibleResponse(
                    triggeredBy: application.buttons["now-playing.back"],
                    visibleElement: importInput
                )
            )
            importToLibraryDurations.append(
                measureVisibleResponse(
                    triggeredBy: application.buttons["import.back"],
                    visibleElement: importButton
                )
            )
            showASCII(in: application)
        }

        for (name, samples) in [
            ("ASCII inspector first change", asciiInspectorDurations),
            ("StockWatch inspector first change", stockWatchInspectorDurations),
            ("PodPin queue inspector first change", queueInspectorDurations),
            ("PodPin library to import first change", libraryToImportDurations),
            ("PodPin import to now playing first change", importToNowPlayingDurations),
            ("PodPin now playing to import first change", nowPlayingToImportDurations),
            ("PodPin import to library first change", importToLibraryDurations),
        ] {
            assertLatencyBudget(
                name,
                samples: samples,
                expectedCount: 30,
                p95Limit: 0.1
            )
        }
    }

    @MainActor
    func testLocalPlaybackStart() throws {
        let application = try launchIsolatedApplication(prefix: "OneBox-LocalPlaybackPerformance")
        defer { application.terminate() }
        importLocalPodPinFixture(in: application)

        let title = application.staticTexts["PodPin 示例音频"]
        XCTAssertTrue(title.waitForExistence(timeout: 2))
        title.doubleClick()

        let playButton = application.buttons["compact-player.play"]
        XCTAssertTrue(playButton.waitForExistence(timeout: 2))
        XCTAssertTrue(waitForValue("正在播放", of: playButton, timeout: 1))
        playButton.click()
        XCTAssertTrue(waitForValue("未播放", of: playButton, timeout: 1))

        var playbackStartDurations: [TimeInterval] = []
        measure(
            metrics: [
                signpostMetric(category: "PodPin", name: "PlaybackStart"),
                XCTMemoryMetric(application: application),
            ],
            options: measureOptions(iterationCount: 30)
        ) {
            let startedAt = ContinuousClock.now
            playButton.click()
            XCTAssertTrue(waitForValue("正在播放", of: playButton, timeout: 1))
            playbackStartDurations.append(
                seconds(in: startedAt.duration(to: ContinuousClock.now))
            )
            playButton.click()
            XCTAssertTrue(waitForValue("未播放", of: playButton, timeout: 1))
        }

        assertLatencyBudget(
            "Local playback click to AVPlayer playing state",
            samples: playbackStartDurations,
            expectedCount: 30,
            p95Limit: 0.3
        )
    }

    @MainActor
    func testTwentyRoundToolSwitchingFootprint() throws {
        let application = try launchIsolatedApplication(prefix: "OneBox-SwitchFootprint")
        defer { application.terminate() }
        warmAllTools(in: application)
        runLoop(for: 2)

        let processID = try oneBoxProcessIdentifier()
        let baseline = try processUsage(for: processID)
        for _ in 0..<20 {
            showStockWatch(in: application)
            showPodPinLibrary(in: application)
            showASCII(in: application)
        }
        runLoop(for: 3)
        let final = try processUsage(for: processID)
        let allowedGrowth = max(baseline.physicalFootprint / 20, 20 * 1_024 * 1_024)
        let growth =
            final.physicalFootprint > baseline.physicalFootprint
            ? final.physicalFootprint - baseline.physicalFootprint
            : 0

        addPerformanceAttachment(
            "baseline_bytes=\(baseline.physicalFootprint)\n"
                + "final_bytes=\(final.physicalFootprint)\n"
                + "growth_bytes=\(growth)\n"
                + "allowed_growth_bytes=\(allowedGrowth)",
            name: "Twenty-round footprint"
        )
        XCTAssertLessThanOrEqual(
            growth,
            allowedGrowth,
            "Physical footprint grew beyond max(5%, 20 MiB) after 20 switch rounds."
        )
        XCTAssertTrue(mainReadyMarker(in: application).exists)
    }

    @MainActor
    func testStaticWorkspaceIdleForSixtySeconds() throws {
        let application = try launchIsolatedApplication(prefix: "OneBox-IdlePerformance")
        defer { application.terminate() }
        showASCII(in: application)
        runLoop(for: 2)

        let processID = try oneBoxProcessIdentifier()
        let dataRootURL = try XCTUnwrap(dataRootURLs.last)
        let filesBefore = try fileSnapshots(in: dataRootURL)
        let usageBefore = try processUsage(for: processID)
        let startedAt = ContinuousClock.now
        runLoop(for: 60)
        let elapsed = seconds(in: startedAt.duration(to: ContinuousClock.now))
        let usageAfter = try processUsage(for: processID)
        let filesAfter = try fileSnapshots(in: dataRootURL)

        let cpuNanoseconds =
            usageAfter.userTime - usageBefore.userTime
            + usageAfter.systemTime - usageBefore.systemTime
        let averageCPUPercent = Double(cpuNanoseconds) / 1_000_000_000 / elapsed * 100
        let bytesRead = usageAfter.bytesRead - usageBefore.bytesRead
        let bytesWritten = usageAfter.bytesWritten - usageBefore.bytesWritten
        addPerformanceAttachment(
            "elapsed_seconds=\(elapsed)\n"
                + "average_cpu_percent=\(averageCPUPercent)\n"
                + "bytes_read=\(bytesRead)\n"
                + "bytes_written=\(bytesWritten)",
            name: "Sixty-second idle usage"
        )

        XCTAssertLessThan(averageCPUPercent, 1, "Static idle CPU must remain below 1%.")
        XCTAssertEqual(
            filesAfter,
            filesBefore,
            "The isolated data root changed while no user task was active."
        )
        XCTAssertTrue(mainReadyMarker(in: application).exists)
        XCTAssertTrue(application.buttons["ascii.inspector-toggle"].isHittable)
    }

    @MainActor
    private func launchIsolatedApplication(prefix: String) throws -> XCUIApplication {
        let application = XCUIApplication()
        _ = try makeConfiguredDataRoot(for: application, prefix: prefix)
        application.launch()
        XCTAssertTrue(mainReadyMarker(in: application).waitForExistence(timeout: 2))
        return application
    }

    @MainActor
    private func makeConfiguredDataRoot(
        for application: XCUIApplication,
        prefix: String
    ) throws -> URL {
        let dataRootURL = try OneBoxUITestSupport.makeDataRoot(prefix: prefix)
        try OneBoxUITestSupport.configure(application, dataRootURL: dataRootURL)
        dataRootURLs.append(dataRootURL)
        return dataRootURL
    }

    @MainActor
    private func warmAllTools(in application: XCUIApplication) {
        showStockWatch(in: application)
        showPodPinLibrary(in: application)
        showASCII(in: application)
    }

    @MainActor
    private func showASCII(in application: XCUIApplication) {
        selectTool("ASCII 工坊", in: application)
        XCTAssertTrue(
            application.descendants(matching: .any)["ascii.workspace"]
                .waitForExistence(timeout: 2)
        )
    }

    @MainActor
    private func showStockWatch(in application: XCUIApplication) {
        selectTool("股票看盘", in: application)
        XCTAssertTrue(application.buttons["添加标的"].waitForExistence(timeout: 2))
    }

    @MainActor
    private func showPodPinLibrary(in application: XCUIApplication) {
        selectTool("PodPin", in: application)
        XCTAssertTrue(application.buttons["workspace.import"].waitForExistence(timeout: 2))
        XCTAssertTrue(podPinReadyContent(in: application).waitForExistence(timeout: 2))
    }

    @MainActor
    private func importLocalPodPinFixture(in application: XCUIApplication) {
        showPodPinLibrary(in: application)
        application.buttons["workspace.import"].click()

        let importInput = application.textViews["import.link-input"]
        XCTAssertTrue(importInput.waitForExistence(timeout: 1))
        importInput.click()
        importInput.typeText(OneBoxUITestSupport.podPinFixtureURLText)

        let saveLocally = application.buttons["import.download-and-save"]
        XCTAssertTrue(saveLocally.waitForExistence(timeout: 2))
        let importEnabled = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "enabled == true"),
            object: saveLocally
        )
        XCTAssertEqual(XCTWaiter.wait(for: [importEnabled], timeout: 2), .completed)
        saveLocally.click()
        XCTAssertTrue(importInput.waitForNonExistence(timeout: 3))
        XCTAssertTrue(application.staticTexts["PodPin 示例音频"].waitForExistence(timeout: 2))
    }

    @MainActor
    private func podPinReadyContent(in application: XCUIApplication) -> XCUIElement {
        application.descendants(matching: .any).matching(
            NSPredicate(
                format: "identifier == %@ OR identifier BEGINSWITH %@",
                "library.empty.title",
                "library.item."
            )
        ).firstMatch
    }

    @MainActor
    private func selectTool(_ name: String, in application: XCUIApplication) {
        let button = application.buttons[name]
        XCTAssertTrue(button.waitForExistence(timeout: 1), "Missing tool button: \(name)")
        button.click()
    }

    @MainActor
    private func measureToolSelection(
        _ name: String,
        readyElement: XCUIElement,
        in application: XCUIApplication
    ) -> TimeInterval {
        let button = application.buttons[name]
        XCTAssertTrue(button.waitForExistence(timeout: 1), "Missing tool button: \(name)")
        return measureVisibleResponse(triggeredBy: button, visibleElement: readyElement)
    }

    @MainActor
    private func measureVisibleResponse(
        triggeredBy trigger: XCUIElement,
        visibleElement: XCUIElement
    ) -> TimeInterval {
        XCTAssertTrue(trigger.exists)
        let startedAt = ContinuousClock.now
        trigger.click()
        XCTAssertTrue(
            visibleElement.waitForExistence(timeout: 1),
            "Expected \(visibleElement) after activating \(trigger)."
        )
        return seconds(in: startedAt.duration(to: ContinuousClock.now))
    }

    @MainActor
    private func waitForValue(
        _ value: String,
        of element: XCUIElement,
        timeout: TimeInterval
    ) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", value),
            object: element
        )
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    @MainActor
    private func mainReadyMarker(in application: XCUIApplication) -> XCUIElement {
        application.descendants(matching: .any)["onebox.main.ready"]
    }

    private func measureOptions(iterationCount: Int) -> XCTMeasureOptions {
        let options = XCTMeasureOptions()
        options.iterationCount = iterationCount
        return options
    }

    private func signpostMetric(category: String, name: String) -> XCTOSSignpostMetric {
        XCTOSSignpostMetric(
            subsystem: "com.cmy.OneBox",
            category: category,
            name: name
        )
    }

    private func seconds(in duration: Duration) -> TimeInterval {
        TimeInterval(duration.components.seconds)
            + TimeInterval(duration.components.attoseconds) / 1_000_000_000_000_000_000
    }

    private func assertLatencyBudget(
        _ name: String,
        samples: [TimeInterval],
        expectedCount: Int,
        p95Limit: TimeInterval
    ) {
        // Match XCTest metrics, which discard the first invocation as warmup.
        let samples = Array(samples.dropFirst())
        XCTAssertEqual(
            samples.count,
            expectedCount,
            "\(name) must retain every measured sample."
        )
        guard samples.count == expectedCount else { return }

        let sortedSamples = samples.sorted()
        let median: TimeInterval
        if sortedSamples.count.isMultiple(of: 2) {
            let upperIndex = sortedSamples.count / 2
            median = (sortedSamples[upperIndex - 1] + sortedSamples[upperIndex]) / 2
        } else {
            median = sortedSamples[sortedSamples.count / 2]
        }
        let p95Index = max(0, Int(ceil(Double(sortedSamples.count) * 0.95)) - 1)
        let p95 = sortedSamples[p95Index]
        let maximum = sortedSamples[sortedSamples.count - 1]
        let sampleText = samples.map { String(format: "%.9f", $0) }.joined(separator: ",")

        addPerformanceAttachment(
            "unit=seconds\n"
                + "sample_count=\(samples.count)\n"
                + "median=\(String(format: "%.9f", median))\n"
                + "p95=\(String(format: "%.9f", p95))\n"
                + "max=\(String(format: "%.9f", maximum))\n"
                + "p95_limit=\(String(format: "%.9f", p95Limit))\n"
                + "samples=\(sampleText)",
            name: name
        )
        XCTAssertLessThanOrEqual(
            p95,
            p95Limit,
            "\(name) P95 was \(String(format: "%.3f", p95 * 1_000)) ms; "
                + "budget is \(String(format: "%.0f", p95Limit * 1_000)) ms."
        )
    }

    @MainActor
    private func oneBoxProcessIdentifier() throws -> pid_t {
        let candidates = NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.cmy.OneBox"
        ).filter { !$0.isTerminated }
        let application = candidates.first(where: { $0.isActive }) ?? candidates.last
        return try XCTUnwrap(application, "OneBox must be running to sample resource usage.")
            .processIdentifier
    }

    private func processUsage(for processID: pid_t) throws -> ProcessUsageSnapshot {
        var usage = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &usage) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { rebound in
                proc_pid_rusage(processID, RUSAGE_INFO_V4, rebound)
            }
        }
        guard result == 0 else {
            throw NSError(
                domain: NSPOSIXErrorDomain,
                code: Int(errno),
                userInfo: [NSLocalizedDescriptionKey: "Could not sample OneBox process usage."]
            )
        }
        return ProcessUsageSnapshot(
            physicalFootprint: usage.ri_phys_footprint,
            userTime: usage.ri_user_time,
            systemTime: usage.ri_system_time,
            bytesRead: usage.ri_diskio_bytesread,
            bytesWritten: usage.ri_diskio_byteswritten
        )
    }

    private func fileSnapshots(in rootURL: URL) throws -> [FileSnapshot] {
        let keys: [URLResourceKey] = [
            .contentModificationDateKey,
            .fileSizeKey,
            .isRegularFileKey,
        ]
        let enumerator = try XCTUnwrap(
            FileManager.default.enumerator(
                at: rootURL,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles]
            )
        )
        let prefixLength = rootURL.path.count + 1
        return try enumerator.compactMap { value in
            guard let url = value as? URL else { return nil }
            let values = try url.resourceValues(forKeys: Set(keys))
            guard values.isRegularFile == true else { return nil }
            return FileSnapshot(
                relativePath: String(url.path.dropFirst(prefixLength)),
                size: values.fileSize ?? 0,
                modificationDate: values.contentModificationDate
            )
        }.sorted { $0.relativePath < $1.relativePath }
    }

    @MainActor
    private func runLoop(for duration: TimeInterval) {
        RunLoop.current.run(until: Date(timeIntervalSinceNow: duration))
    }

    private func addPerformanceAttachment(_ contents: String, name: String) {
        let attachment = XCTAttachment(string: contents)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
