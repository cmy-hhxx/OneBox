import AppKit
import Foundation
import SwiftUI
import XCTest

@testable import PodPinTool

@MainActor
final class WorkspacePerformanceTests: XCTestCase {
    private let metrics: [XCTMetric] = [XCTClockMetric(), XCTMemoryMetric()]

    func testHundredAudioFirstScreenBaseline() {
        let rows = makeRows(count: 100)
        let downloadSession = DownloadSession()
        let timeline = PlaybackTimelineSession()
        autoreleasepool {
            let host = NSHostingView(
                rootView: AudioRowsBenchmarkRoot(
                    rows: rows,
                    downloadSession: downloadSession,
                    timeline: timeline
                )
            )
            host.frame = NSRect(x: 0, y: 0, width: 720, height: 640)
            host.layoutSubtreeIfNeeded()
        }
        var durations: [TimeInterval] = []

        measure(metrics: metrics, options: options) {
            let start = ProcessInfo.processInfo.systemUptime
            autoreleasepool {
                let host = NSHostingView(
                    rootView: AudioRowsBenchmarkRoot(
                        rows: rows,
                        downloadSession: downloadSession,
                        timeline: timeline
                    )
                )
                host.frame = NSRect(x: 0, y: 0, width: 720, height: 640)
                host.layoutSubtreeIfNeeded()
                XCTAssertEqual(host.bounds.height, 640)
            }
            durations.append(ProcessInfo.processInfo.systemUptime - start)
        }
        assertP95(durations, isBelow: 0.1, scenario: "PodPin 100-row first screen")
    }

    func testThousandFolderTreeOpenAndSelectionBaseline() {
        let persistedFolders = makePersistedFolders(totalCount: 1_000)
        let selectedFolderID = persistedFolders.last!.id
        var durations: [TimeInterval] = []
        renderFolderScenario(
            persistedFolders: persistedFolders,
            selectedFolderID: selectedFolderID
        )

        measure(metrics: metrics, options: options) {
            let start = ProcessInfo.processInfo.systemUptime
            autoreleasepool {
                self.renderFolderScenario(
                    persistedFolders: persistedFolders,
                    selectedFolderID: selectedFolderID
                )
            }
            durations.append(ProcessInfo.processInfo.systemUptime - start)
        }
        assertP95(durations, isBelow: 0.1, scenario: "PodPin 1,000-folder tree")
    }

    func testPlaybackTimelineUpdateDoesNotRebuildFolderTreeBaseline() {
        let timeline = PlaybackTimelineSession()
        let folders = LibraryFolderTreeBuilder.buildSynchronously(
            from: makePersistedFolders(totalCount: 1_000)
        )
        let host = NSHostingView(
            rootView: FolderTreeWithTimelineBenchmarkRoot(folders: folders, timeline: timeline)
        )
        host.frame = NSRect(x: 0, y: 0, width: 320, height: 640)
        host.layoutSubtreeIfNeeded()
        renderTimelineUpdates(timeline: timeline, host: host)
        var durations: [TimeInterval] = []

        measure(metrics: metrics, options: options) {
            let start = ProcessInfo.processInfo.systemUptime
            self.renderTimelineUpdates(timeline: timeline, host: host)
            durations.append(ProcessInfo.processInfo.systemUptime - start)
        }
        assertP95(durations, isBelow: 0.1, scenario: "PodPin playback timeline updates")
    }

    func testTenThousandFolderTreeP95Budget() {
        let persistedFolders = makePersistedFolders(totalCount: 10_000)
        let selectedFolderID = persistedFolders.last!.id
        var durations: [TimeInterval] = []
        renderFolderScenario(
            persistedFolders: persistedFolders,
            selectedFolderID: selectedFolderID
        )

        measure(metrics: [XCTClockMetric()], options: options) {
            let start = ProcessInfo.processInfo.systemUptime
            autoreleasepool {
                self.renderFolderScenario(
                    persistedFolders: persistedFolders,
                    selectedFolderID: selectedFolderID
                )
            }
            durations.append(ProcessInfo.processInfo.systemUptime - start)
        }

        assertP95(durations, isBelow: 0.2, scenario: "PodPin 10,000-folder tree")
    }

    private var options: XCTMeasureOptions {
        let options = XCTMeasureOptions()
        options.iterationCount = 30
        return options
    }

    private func renderTimelineUpdates(
        timeline: PlaybackTimelineSession,
        host: NSHostingView<FolderTreeWithTimelineBenchmarkRoot>
    ) {
        for second in 0..<20 {
            timeline.update(
                PlaybackTimelineSnapshot(
                    currentTime: TimeInterval(second),
                    duration: 1_800
                )
            )
            host.layoutSubtreeIfNeeded()
        }
    }

    private func assertP95(
        _ durations: [TimeInterval],
        isBelow budget: TimeInterval,
        scenario: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let sorted = durations.sorted()
        let index = max(0, Int(ceil(Double(sorted.count) * 0.95)) - 1)
        let p95 = sorted[index]
        XCTAssertLessThan(
            p95,
            budget,
            "\(scenario) P95 was \(p95)s; budget is \(budget)s",
            file: file,
            line: line
        )
    }

    private func makeRows(count: Int) -> [LibraryItemRow] {
        (0..<count).map { index in
            LibraryItemRow(
                id: UUID(),
                title: "性能音频 \(index)",
                author: "作者 \(index)",
                sourceName: "离线基准",
                duration: 1_800,
                importedAt: Date(timeIntervalSince1970: 1_700_000_000 + Double(index)),
                storageState: .downloaded
            )
        }
    }

    private func makePersistedFolders(totalCount: Int) -> [LibraryFolder] {
        let ids = (0..<totalCount).map { index in
            index == 0 ? LibraryFolder.inboxID : UUID()
        }
        return ids.enumerated().map { index, id in
            LibraryFolder(
                id: id,
                parentID: index == 0 ? nil : ids[(index - 1) / 8],
                name: index == 0 ? "Inbox" : "文件夹 \(index)",
                systemKind: index == 0 ? .inbox : .user,
                createdAt: Date(timeIntervalSince1970: TimeInterval(index))
            )
        }
    }

    private func renderFolderScenario(
        persistedFolders: [LibraryFolder],
        selectedFolderID: UUID
    ) {
        let folders = LibraryFolderTreeBuilder.buildSynchronously(from: persistedFolders)
        let expanded = LibraryFolderOutline.initiallyExpandedFolderIDs(
            in: folders,
            selectedFolderID: selectedFolderID
        )
        let visibleRows = LibraryFolderOutline.visibleRows(
            in: folders,
            expandedFolderIDs: expanded,
            excluding: []
        )
        XCTAssertTrue(visibleRows.contains { $0.id == selectedFolderID })

        let host = NSHostingView(
            rootView: FolderTreeBenchmarkRoot(
                folders: folders,
                selectedFolderID: selectedFolderID
            )
        )
        host.frame = NSRect(x: 0, y: 0, width: 320, height: 640)
        host.layoutSubtreeIfNeeded()
        XCTAssertEqual(host.bounds.height, 640)
    }
}

@MainActor
private struct AudioRowsBenchmarkRoot: View {
    let rows: [LibraryItemRow]
    let downloadSession: DownloadSession
    let timeline: PlaybackTimelineSession

    var body: some View {
        List(rows) { row in
            LibraryItemRowView(
                item: row,
                isSelected: false,
                isCurrentItem: false,
                isPlaying: false,
                downloadSession: downloadSession,
                playbackTimeline: timeline,
                onTogglePlayback: {},
                onItemAction: { _ in }
            )
            .listRowInsets(EdgeInsets())
        }
        .listStyle(.plain)
    }
}

@MainActor
private struct FolderTreeBenchmarkRoot: View {
    let folders: [LibraryFolderNode]
    let selectedFolderID: UUID?

    var body: some View {
        LibraryFolderTreePicker(
            folders: folders,
            selectedFolderID: selectedFolderID,
            onSelect: { _ in }
        )
    }
}

@MainActor
private struct FolderTreeWithTimelineBenchmarkRoot: View {
    let folders: [LibraryFolderNode]
    @ObservedObject var timeline: PlaybackTimelineSession

    var body: some View {
        HStack(spacing: 0) {
            LibraryFolderTreePicker(folders: folders, onSelect: { _ in })
            Text(timeline.snapshot.currentTime, format: .number.precision(.fractionLength(0)))
                .frame(width: 1)
                .accessibilityHidden(true)
        }
    }
}
