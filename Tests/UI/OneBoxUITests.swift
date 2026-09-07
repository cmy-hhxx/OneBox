import XCTest

final class OneBoxUITests: XCTestCase {
    private enum HorizontalPosition {
        case leading
        case trailing
    }

    private var app: XCUIApplication!
    private var dataRootURL: URL!

    override func setUpWithError() throws {
        continueAfterFailure = false

        dataRootURL = try OneBoxUITestSupport.makeDataRoot(prefix: "OneBox-UITests")
    }

    override func tearDownWithError() throws {
        if let dataRootURL {
            OneBoxUITestSupport.cleanUp(dataRootURL: dataRootURL)
        }

        app = nil
        dataRootURL = nil
    }

    @MainActor
    func testMainToolSwitchingAndInspectorEscape() throws {
        app = try makeApplication()
        defer { app.terminate() }
        let window = launchAndWaitForMainWindow()

        selectTool("ASCII 工坊")
        let asciiWorkspace = app.descendants(matching: .any)["ascii.workspace"]
        let asciiInspectorToggle = app.buttons["ascii.inspector-toggle"]
        let asciiInspectorClose = app.buttons["关闭参数"]
        XCTAssertTrue(asciiWorkspace.waitForExistence(timeout: 5))
        XCTAssertTrue(asciiInspectorToggle.waitForExistence(timeout: 5))
        XCTAssertFalse(asciiInspectorClose.exists)
        asciiInspectorToggle.click()
        XCTAssertTrue(asciiInspectorClose.waitForExistence(timeout: 5))
        let inspectorOpenFrame = asciiWorkspace.frame
        XCTAssertGreaterThan(
            asciiInspectorClose.frame.midX,
            inspectorOpenFrame.midX,
            "The ASCII inspector must be presented on the trailing side."
        )

        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(asciiInspectorClose.waitForNonExistence(timeout: 3))
        let contentExpanded = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                asciiWorkspace.frame.width >= inspectorOpenFrame.width + 200
            },
            object: nil
        )
        XCTAssertEqual(XCTWaiter.wait(for: [contentExpanded], timeout: 3), .completed)
        XCTAssertEqual(asciiWorkspace.frame.minX, inspectorOpenFrame.minX, accuracy: 4)
        XCTAssertGreaterThan(asciiWorkspace.frame.maxX, inspectorOpenFrame.maxX + 200)

        // Reverse while the native inspector is still settling. The same command
        // must remain actionable instead of being locked behind the transition.
        asciiInspectorToggle.click()
        XCTAssertTrue(asciiInspectorClose.waitForExistence(timeout: 1))
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(asciiInspectorClose.waitForNonExistence(timeout: 1))
        asciiInspectorToggle.click()
        XCTAssertTrue(asciiInspectorClose.waitForExistence(timeout: 3))

        selectTool("股票看盘")
        let stockWatchReady = app.buttons["添加标的"]
        XCTAssertTrue(stockWatchReady.waitForExistence(timeout: 8))
        let stockInspectorClose = app.buttons["关闭检查器"]
        let initialShowInspector = app.buttons["显示检查器"]
        XCTAssertTrue(initialShowInspector.waitForExistence(timeout: 5))
        initialShowInspector.click()
        XCTAssertTrue(stockInspectorClose.waitForExistence(timeout: 5))
        let stockToolbarToggle = positionedButton(
            labeled: "关闭检查器",
            at: .leading,
            minimumCount: 2
        )
        let stockInspectorCloseButton = positionedButton(
            labeled: "关闭检查器",
            at: .trailing,
            minimumCount: 2
        )
        XCTAssertGreaterThan(
            stockInspectorCloseButton.frame.minX,
            stockToolbarToggle.frame.maxX,
            "The StockWatch inspector must trail the workspace instead of overlaying it."
        )

        // A task sheet owns Escape before the inspector underneath it.
        stockWatchReady.click()
        let closeAddInstrument = app.buttons["关闭添加标的"]
        XCTAssertTrue(closeAddInstrument.waitForExistence(timeout: 3))
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(closeAddInstrument.waitForNonExistence(timeout: 3))
        XCTAssertTrue(stockInspectorClose.exists)

        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(stockInspectorClose.waitForNonExistence(timeout: 3))
        let showInspector = app.buttons["显示检查器"]
        XCTAssertTrue(showInspector.waitForExistence(timeout: 3))
        XCTAssertGreaterThan(
            showInspector.frame.minX,
            stockToolbarToggle.frame.minX + 200,
            "Closing the StockWatch inspector must expand the workspace to the trailing edge."
        )

        // Open and immediately reverse before presentation settles.
        showInspector.click()
        XCTAssertTrue(stockInspectorClose.waitForExistence(timeout: 1))
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(showInspector.waitForExistence(timeout: 1))
        showInspector.click()
        XCTAssertTrue(stockInspectorClose.waitForExistence(timeout: 3))

        selectTool("ASCII 工坊")
        XCTAssertTrue(app.buttons["关闭参数"].waitForExistence(timeout: 5))
        XCTAssertTrue(window.exists)

        let stockWatchDatabase =
            dataRootURL
            .appendingPathComponent("OneBox/StockWatch", isDirectory: true)
            .appendingPathComponent("marketsprite.sqlite", isDirectory: false)
        XCTAssertTrue(FileManager.default.fileExists(atPath: stockWatchDatabase.path))
    }

    @MainActor
    func testPodPinRoutesQueueGeometryAndEscapeOrder() throws {
        app = try makeApplication()
        defer { app.terminate() }
        let window = launchAndWaitForMainWindow()

        selectTool("PodPin")
        let importButton = app.buttons["workspace.import"]
        XCTAssertTrue(importButton.waitForExistence(timeout: 8))
        importButton.click()

        let importInput = app.textViews["import.link-input"]
        XCTAssertTrue(importInput.waitForExistence(timeout: 5))
        let importBack = app.buttons["import.back"]
        XCTAssertTrue(importBack.waitForExistence(timeout: 3))
        XCTAssertEqual(importBack.label, "返回资料库")
        let draft = "draft retained across routes"
        importInput.click()
        importInput.typeText(draft)

        let nowPlaying = app.buttons["workspace.now-playing"]
        XCTAssertTrue(nowPlaying.waitForExistence(timeout: 8))
        nowPlaying.click()

        let player = app.otherElements["now-playing.player"]
        XCTAssertTrue(player.waitForExistence(timeout: 5))
        let nowPlayingBack = app.buttons["now-playing.back"]
        XCTAssertTrue(nowPlayingBack.waitForExistence(timeout: 3))
        XCTAssertEqual(nowPlayingBack.label, "返回导入")
        let queueToggle = app.buttons["now-playing.queue-toggle"]
        XCTAssertTrue(queueToggle.waitForExistence(timeout: 3))
        let queueClosedPlayerFrame = player.frame
        queueToggle.click()

        let queue = app.otherElements["now-playing.queue"]
        XCTAssertTrue(queue.waitForExistence(timeout: 5))
        let queuePushedContent = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                player.frame.width <= queueClosedPlayerFrame.width - 260
            },
            object: nil
        )
        XCTAssertEqual(XCTWaiter.wait(for: [queuePushedContent], timeout: 3), .completed)
        let queueOpenPlayerFrame = player.frame
        XCTAssertEqual(queueOpenPlayerFrame.minX, queueClosedPlayerFrame.minX, accuracy: 4)
        XCTAssertGreaterThanOrEqual(queue.frame.minX, queueOpenPlayerFrame.maxX - 4)
        XCTAssertLessThanOrEqual(queue.frame.maxX, window.frame.maxX + 4)

        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(queue.waitForNonExistence(timeout: 3))
        XCTAssertTrue(player.exists)
        let queueClosedAgain = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                player.frame.width >= queueOpenPlayerFrame.width + 260
            },
            object: nil
        )
        XCTAssertEqual(XCTWaiter.wait(for: [queueClosedAgain], timeout: 3), .completed)

        // The queue can reverse immediately in either direction without locking input.
        queueToggle.click()
        XCTAssertTrue(queue.waitForExistence(timeout: 1))
        queueToggle.click()
        XCTAssertTrue(queue.waitForNonExistence(timeout: 1))
        queueToggle.click()
        XCTAssertTrue(queue.waitForExistence(timeout: 3))

        // Escape dismisses the trailing inspector before popping the drill-in route.
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(queue.waitForNonExistence(timeout: 3))
        XCTAssertTrue(player.exists)
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(player.waitForNonExistence(timeout: 3))
        XCTAssertTrue(importInput.waitForExistence(timeout: 3))
        XCTAssertEqual(importInput.value as? String, draft)

        // The reverse route is import -> library and Escape at the root is a no-op.
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(importInput.waitForNonExistence(timeout: 3))
        let rootImportButton = app.buttons["workspace.import"]
        XCTAssertTrue(rootImportButton.waitForExistence(timeout: 3))
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(rootImportButton.exists)

        // Both semantic back buttons follow the same reverse stack as Escape.
        rootImportButton.click()
        XCTAssertTrue(importInput.waitForExistence(timeout: 3))
        app.buttons["workspace.now-playing"].click()
        XCTAssertTrue(nowPlayingBack.waitForExistence(timeout: 3))
        nowPlayingBack.click()
        XCTAssertTrue(importInput.waitForExistence(timeout: 3))
        importBack.click()
        XCTAssertTrue(rootImportButton.waitForExistence(timeout: 3))

        let rootNowPlayingButton = app.buttons["workspace.now-playing"]
        rootNowPlayingButton.click()
        XCTAssertTrue(nowPlayingBack.waitForExistence(timeout: 3))
        XCTAssertEqual(nowPlayingBack.label, "返回资料库")
        nowPlayingBack.click()
        XCTAssertTrue(rootImportButton.waitForExistence(timeout: 3))

        let podPinDatabase =
            dataRootURL
            .appendingPathComponent("PodPin", isDirectory: true)
            .appendingPathComponent("podpin.sqlite", isDirectory: false)
        XCTAssertTrue(FileManager.default.fileExists(atPath: podPinDatabase.path))
    }

    @MainActor
    func testPodPinReduceMotionRouteFramesDoNotMoveHorizontally() throws {
        app = try makeApplication(
            additionalArguments: [OneBoxUITestSupport.reduceMotionLaunchArgument]
        )
        defer { app.terminate() }
        _ = launchAndWaitForMainWindow()

        selectTool("PodPin")
        let importButton = app.buttons["workspace.import"]
        XCTAssertTrue(importButton.waitForExistence(timeout: 8))
        importButton.click()

        let importInput = app.textViews["import.link-input"]
        XCTAssertTrue(importInput.waitForExistence(timeout: 5))
        let nowPlayingButton = app.buttons["workspace.now-playing"]
        XCTAssertTrue(nowPlayingButton.waitForExistence(timeout: 3))
        let player = app.otherElements["now-playing.player"]

        let pushSamples = sampleRouteTransitionFrames(
            outgoing: importInput,
            incoming: player,
            action: { nowPlayingButton.click() }
        )
        assertNoHorizontalDisplacement(
            pushSamples,
            transitionName: "Reduce Motion push"
        )

        let nowPlayingBack = app.buttons["now-playing.back"]
        XCTAssertTrue(nowPlayingBack.waitForExistence(timeout: 3))
        let popSamples = sampleRouteTransitionFrames(
            outgoing: player,
            incoming: importInput,
            action: { nowPlayingBack.click() }
        )
        assertNoHorizontalDisplacement(
            popSamples,
            transitionName: "Reduce Motion pop"
        )
    }

    @MainActor
    func testPodPinImportDraftAndCollectionChangesReturnToLibrary() throws {
        app = try makeApplication()
        defer { app.terminate() }
        _ = launchAndWaitForMainWindow()

        selectTool("PodPin")
        let rootImportButton = app.buttons["workspace.import"]
        XCTAssertTrue(rootImportButton.waitForExistence(timeout: 8))

        let folderActions = app.descendants(matching: .any)["library.folder-actions"]
        XCTAssertTrue(folderActions.waitForExistence(timeout: 3))
        folderActions.click()
        let createRootFolder = app.menuItems["新建根文件夹"]
        XCTAssertTrue(createRootFolder.waitForExistence(timeout: 3))
        createRootFolder.click()

        let folderName = "UI Test Archive"
        let folderNameField = app.textFields["library.folder-editor.name"]
        XCTAssertTrue(folderNameField.waitForExistence(timeout: 3))
        folderNameField.click()
        folderNameField.typeText(folderName)
        let saveFolder = app.buttons["library.folder-editor.save"]
        XCTAssertTrue(saveFolder.waitForExistence(timeout: 3))
        saveFolder.click()
        XCTAssertTrue(folderNameField.waitForNonExistence(timeout: 5))

        let collectionPicker = app.buttons["选择资料集合或文件夹"]
        XCTAssertTrue(collectionPicker.waitForExistence(timeout: 3))
        XCTAssertEqual(collectionPicker.value as? String, folderName)
        rootImportButton.click()

        let importInput = app.textViews["import.link-input"]
        XCTAssertTrue(importInput.waitForExistence(timeout: 3))
        importInput.click()
        importInput.typeText(OneBoxUITestSupport.podPinCollectionFixtureURLText)

        let selectedSecondPart = app.buttons["取消选择 PodPin 示例分段 2"]
        XCTAssertTrue(selectedSecondPart.waitForExistence(timeout: 5))
        selectedSecondPart.click()
        let deselectedSecondPart = app.buttons["选择 PodPin 示例分段 2"]
        XCTAssertTrue(deselectedSecondPart.waitForExistence(timeout: 3))

        let destination = app.buttons["import.destination"]
        XCTAssertTrue(destination.waitForExistence(timeout: 3))
        XCTAssertEqual(destination.value as? String, folderName)

        app.buttons["workspace.now-playing"].click()
        let nowPlayingBack = app.buttons["now-playing.back"]
        XCTAssertTrue(nowPlayingBack.waitForExistence(timeout: 3))
        XCTAssertEqual(nowPlayingBack.label, "返回导入")
        nowPlayingBack.click()

        XCTAssertTrue(importInput.waitForExistence(timeout: 3))
        XCTAssertEqual(
            importInput.value as? String,
            OneBoxUITestSupport.podPinCollectionFixtureURLText
        )
        XCTAssertEqual(destination.value as? String, folderName)
        XCTAssertTrue(app.buttons["取消选择 PodPin 示例分段 1"].exists)
        XCTAssertTrue(deselectedSecondPart.exists)
        XCTAssertTrue(app.buttons["取消选择 PodPin 示例分段 3"].exists)

        // Switching the collection while drilled in pops to the library root.
        collectionPicker.click()
        let recentlyImported = app.buttons["最近导入"]
        XCTAssertTrue(recentlyImported.waitForExistence(timeout: 3))
        recentlyImported.click()
        XCTAssertTrue(importInput.waitForNonExistence(timeout: 3))
        XCTAssertTrue(rootImportButton.waitForExistence(timeout: 3))
        XCTAssertEqual(collectionPicker.value as? String, "最近导入")

        // A deterministic local import also returns to the library after success.
        rootImportButton.click()
        XCTAssertTrue(importInput.waitForExistence(timeout: 3))
        importInput.click()
        importInput.typeText(OneBoxUITestSupport.podPinFixtureURLText)
        let saveLocally = app.buttons["import.download-and-save"]
        XCTAssertTrue(saveLocally.waitForExistence(timeout: 5))
        let importEnabled = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "enabled == true"),
            object: saveLocally
        )
        XCTAssertEqual(XCTWaiter.wait(for: [importEnabled], timeout: 5), .completed)
        saveLocally.click()
        XCTAssertTrue(importInput.waitForNonExistence(timeout: 8))
        XCTAssertTrue(rootImportButton.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["PodPin 示例音频"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testWindowSupportsDefaultMinimumWideAndTallLayouts() throws {
        app = try makeApplication(additionalArguments: ["--ui-default"])
        defer { app.terminate() }
        let window = launchAndWaitForMainWindow()
        assertWindowSize(window, width: 1_048, height: 648, accuracy: 35)
        assertControlIsInsideWindow(app.buttons["ascii.inspector-toggle"], window: window)
        assertNoVisibleHorizontalScrollBar(in: window)

        let defaultFrame = window.frame
        resize(window, edge: CGVector(dx: 0.998, dy: 0.5), by: CGVector(dx: 180, dy: 0))
        waitForWindow(window, timeout: 5) { frame in
            frame.width >= defaultFrame.width + 100
                && abs(frame.height - defaultFrame.height) < 35
        }
        let wideFrame = window.frame
        selectTool("股票看盘")
        let addInstrument = app.buttons["添加标的"]
        XCTAssertTrue(addInstrument.waitForExistence(timeout: 8))
        assertControlIsInsideWindow(addInstrument, window: window)
        assertNoVisibleHorizontalScrollBar(in: window)

        resize(window, edge: CGVector(dx: 0.998, dy: 0.5), by: CGVector(dx: -180, dy: 0))
        waitForWindow(window, timeout: 5) { frame in
            abs(frame.width - defaultFrame.width) < 50
                && abs(frame.height - defaultFrame.height) < 35
        }
        let restoredFrame = window.frame
        resize(window, edge: CGVector(dx: 0.5, dy: 0.998), by: CGVector(dx: 0, dy: 140))
        if !windowMatches(
            window, timeout: 1,
            matching: { frame in
                frame.height >= restoredFrame.height + 80
            })
        {
            // XCTest's vertical screen-coordinate direction has differed between
            // macOS runners. Reverse the same resize edge if the first drag shrank.
            resize(window, edge: CGVector(dx: 0.5, dy: 0.998), by: CGVector(dx: 0, dy: -280))
        }
        waitForWindow(window, timeout: 5) { frame in
            frame.height >= restoredFrame.height + 80
                && abs(frame.width - restoredFrame.width) < 35
        }
        XCTAssertLessThan(window.frame.width, wideFrame.width - 100)
        selectTool("PodPin")
        let importButton = app.buttons["workspace.import"]
        XCTAssertTrue(importButton.waitForExistence(timeout: 8))
        assertControlIsInsideWindow(importButton, window: window)
        assertNoVisibleHorizontalScrollBar(in: window)

        app.terminate()
        app = try makeApplication(additionalArguments: ["--ui-minimum"])
        let minimumWindow = launchAndWaitForMainWindow()
        assertWindowSize(minimumWindow, width: 899, height: 556, accuracy: 35)
        selectTool("ASCII 工坊")
        let minimumInspectorToggle = app.buttons["ascii.inspector-toggle"]
        XCTAssertTrue(minimumInspectorToggle.waitForExistence(timeout: 5))
        assertControlIsInsideWindow(minimumInspectorToggle, window: minimumWindow)
        assertNoVisibleHorizontalScrollBar(in: minimumWindow)
        app.terminate()
    }

    @discardableResult
    @MainActor
    private func launchAndWaitForMainWindow() -> XCUIElement {
        app.launch()
        let window = app.windows["OneBox"].firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 8))
        XCTAssertTrue(
            app.descendants(matching: .any)["onebox.main.ready"]
                .waitForExistence(timeout: 8)
        )
        return window
    }

    @MainActor
    private func selectTool(_ name: String) {
        let button = app.buttons[name]
        XCTAssertTrue(button.waitForExistence(timeout: 5), "Missing tool button: \(name)")
        button.click()
    }

    @MainActor
    private func makeApplication(additionalArguments: [String] = []) throws -> XCUIApplication {
        let app = XCUIApplication()
        try OneBoxUITestSupport.configure(
            app,
            dataRootURL: dataRootURL,
            additionalArguments: additionalArguments
        )
        return app
    }

    private struct RouteTransitionFrameSamples {
        let outgoingBeforeTransition: CGRect
        let outgoingDuringTransition: [CGRect]
        let incomingDuringTransition: [CGRect]
        let incomingAfterTransition: CGRect
    }

    @MainActor
    private func sampleRouteTransitionFrames(
        outgoing: XCUIElement,
        incoming: XCUIElement,
        action: () -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> RouteTransitionFrameSamples {
        XCTAssertTrue(outgoing.exists, file: file, line: line)
        let outgoingBeforeTransition = outgoing.frame
        action()

        var outgoingDuringTransition: [CGRect] = []
        var incomingDuringTransition: [CGRect] = []
        let deadline = ProcessInfo.processInfo.systemUptime + 0.15
        while ProcessInfo.processInfo.systemUptime < deadline {
            guard outgoing.exists, incoming.exists else { continue }
            let outgoingFrame = outgoing.frame
            let incomingFrame = incoming.frame
            guard !outgoingFrame.isEmpty, !incomingFrame.isEmpty else { continue }
            outgoingDuringTransition.append(outgoingFrame)
            incomingDuringTransition.append(incomingFrame)
        }

        XCTAssertGreaterThanOrEqual(
            outgoingDuringTransition.count,
            2,
            "The test must observe multiple live frames while both routes overlap.",
            file: file,
            line: line
        )
        XCTAssertTrue(incoming.waitForExistence(timeout: 3), file: file, line: line)
        return RouteTransitionFrameSamples(
            outgoingBeforeTransition: outgoingBeforeTransition,
            outgoingDuringTransition: outgoingDuringTransition,
            incomingDuringTransition: incomingDuringTransition,
            incomingAfterTransition: incoming.frame
        )
    }

    private func assertNoHorizontalDisplacement(
        _ samples: RouteTransitionFrameSamples,
        transitionName: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for frame in samples.outgoingDuringTransition {
            XCTAssertEqual(
                frame.minX,
                samples.outgoingBeforeTransition.minX,
                accuracy: 2,
                "\(transitionName) moved the outgoing route horizontally.",
                file: file,
                line: line
            )
        }
        for frame in samples.incomingDuringTransition {
            XCTAssertEqual(
                frame.minX,
                samples.incomingAfterTransition.minX,
                accuracy: 2,
                "\(transitionName) moved the incoming route horizontally.",
                file: file,
                line: line
            )
        }
    }

    @MainActor
    private func positionedButton(
        labeled label: String,
        at position: HorizontalPosition,
        minimumCount: Int
    ) -> XCUIElement {
        let query = app.buttons.matching(NSPredicate(format: "label == %@", label))
        let countReached = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in query.count >= minimumCount },
            object: nil
        )
        XCTAssertEqual(XCTWaiter.wait(for: [countReached], timeout: 3), .completed)
        let buttons = query.allElementsBoundByIndex
        XCTAssertGreaterThanOrEqual(buttons.count, minimumCount)
        switch position {
        case .leading:
            return buttons.min(by: { $0.frame.minX < $1.frame.minX }) ?? query.firstMatch
        case .trailing:
            return buttons.max(by: { $0.frame.maxX < $1.frame.maxX }) ?? query.firstMatch
        }
    }

    @MainActor
    private func resize(
        _ window: XCUIElement,
        edge: CGVector,
        by offset: CGVector
    ) {
        let handle = window.coordinate(withNormalizedOffset: edge)
        handle.press(forDuration: 0.1, thenDragTo: handle.withOffset(offset))
    }

    @MainActor
    private func waitForWindow(
        _ window: XCUIElement,
        timeout: TimeInterval,
        matching condition: @escaping (CGRect) -> Bool
    ) {
        XCTAssertTrue(windowMatches(window, timeout: timeout, matching: condition))
    }

    @MainActor
    private func windowMatches(
        _ window: XCUIElement,
        timeout: TimeInterval,
        matching condition: @escaping (CGRect) -> Bool
    ) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in condition(window.frame) },
            object: nil
        )
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    @MainActor
    private func assertWindowSize(
        _ window: XCUIElement,
        width: CGFloat,
        height: CGFloat,
        accuracy: CGFloat,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(window.frame.width, width, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(window.frame.height, height, accuracy: accuracy, file: file, line: line)
    }

    @MainActor
    private func assertControlIsInsideWindow(
        _ control: XCUIElement,
        window: XCUIElement,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(control.exists, file: file, line: line)
        XCTAssertTrue(control.isHittable, file: file, line: line)
        XCTAssertGreaterThanOrEqual(
            control.frame.minX, window.frame.minX - 4, file: file, line: line)
        XCTAssertLessThanOrEqual(control.frame.maxX, window.frame.maxX + 4, file: file, line: line)
        XCTAssertGreaterThanOrEqual(
            control.frame.minY, window.frame.minY - 4, file: file, line: line)
        XCTAssertLessThanOrEqual(control.frame.maxY, window.frame.maxY + 4, file: file, line: line)
    }

    @MainActor
    private func assertNoVisibleHorizontalScrollBar(
        in window: XCUIElement,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let visibleHorizontalScrollBars = app.scrollBars.allElementsBoundByIndex.filter {
            scrollBar in
            let frame = scrollBar.frame
            return scrollBar.isHittable
                && frame.intersects(window.frame)
                && frame.width > max(frame.height * 2, 100)
        }
        XCTAssertTrue(
            visibleHorizontalScrollBars.isEmpty,
            "The main window must not expose a horizontal scroll bar.",
            file: file,
            line: line
        )
    }
}
