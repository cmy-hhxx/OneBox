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

        measure(metrics: metrics, options: options) {
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
        }
    }

    func testThousandFolderTreeOpenAndSelectionBaseline() {
        let folders = makeFolderTree(totalCount: 1_000)

        measure(metrics: metrics, options: options) {
            autoreleasepool {
                let host = NSHostingView(
                    rootView: FolderTreeBenchmarkRoot(
                        folders: folders,
                        selectedFolderID: folders.last?.id
                    )
                )
                host.frame = NSRect(x: 0, y: 0, width: 320, height: 640)
                host.layoutSubtreeIfNeeded()
                XCTAssertEqual(host.bounds.height, 640)
            }
        }
    }

    func testPlaybackTimelineUpdateDoesNotRebuildFolderTreeBaseline() {
        let timeline = PlaybackTimelineSession()
        let folders = makeFolderTree(totalCount: 1_000)
        let host = NSHostingView(
            rootView: FolderTreeWithTimelineBenchmarkRoot(folders: folders, timeline: timeline)
        )
        host.frame = NSRect(x: 0, y: 0, width: 320, height: 640)
        host.layoutSubtreeIfNeeded()

        measure(metrics: metrics, options: options) {
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
    }

    private var options: XCTMeasureOptions {
        let options = XCTMeasureOptions()
        options.iterationCount = 3
        return options
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

    private func makeFolderTree(totalCount: Int) -> [LibraryFolderNode] {
        let inbox = LibraryFolderNode(
            id: LibraryFolder.inboxID,
            name: "收件箱",
            isSystemFolder: true
        )
        let branchCount = 10
        let remaining = max(totalCount - 1, branchCount)
        let baseCount = remaining / branchCount
        let extraCount = remaining % branchCount
        let branches = (0..<branchCount).map { branch in
            folderChain(
                branch: branch,
                depth: 0,
                count: baseCount + (branch < extraCount ? 1 : 0)
            )
        }
        return [inbox] + branches
    }

    private func folderChain(
        branch: Int,
        depth: Int,
        count: Int
    ) -> LibraryFolderNode {
        LibraryFolderNode(
            id: UUID(),
            name: "文件夹 \(branch)-\(depth)",
            children: count > 1
                ? [folderChain(branch: branch, depth: depth + 1, count: count - 1)]
                : []
        )
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
