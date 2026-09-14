import AppKit
import Foundation
import OneBoxDesignSystem
import SwiftUI
import XCTest

@testable import StockWatchTool

/// Local rendering diagnostic; opt in on an idle Mac with a visible display.
/// NSView update delivery is not a measurement of compositor presentation or GPU hitches.
@MainActor
final class StockWatchAnimationPerformanceTests: XCTestCase {
    func testWorkspaceWidthAnimationUpdateDelivery() async throws {
        guard
            let reportPath = ProcessInfo.processInfo.environment[
                "ONEBOX_ANIMATION_PERFORMANCE_REPORT"]
        else {
            throw XCTSkip("Set ONEBOX_ANIMATION_PERFORMANCE_REPORT for the local timing harness.")
        }

        let database = try MarketDatabase.inMemory()
        let instruments = Instrument.initialWatchlist
        let snapshots = Dictionary(
            uniqueKeysWithValues: try instruments.map { ($0.id, try Self.snapshot(for: $0)) })
        for instrument in instruments {
            try await database.saveQuote(
                try XCTUnwrap(snapshots[instrument.id]), for: instrument)
        }
        let suiteName = "OneBox.AnimationPerformance.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = StockWatchPreferences(defaults: defaults, legacyDefaults: nil)
        let store = MonitorStore(
            client: AnimationPerformanceMarketDataClient(snapshots: snapshots),
            database: database,
            preferences: preferences,
            refreshNow: { market in
                instruments.first(where: { $0.market == market })
                    .flatMap { snapshots[$0.id]?.receivedAt } ?? Date()
            }
        )
        try await store.start()
        await store.refreshAll()
        XCTAssertEqual(store.watchlistPresentation.instruments.count, instruments.count)

        let model = WidthAnimationModel()
        let recorder = WidthAnimationRecorder()
        let host = NSHostingView(
            rootView: WidthAnimationHarness(
                model: model, recorder: recorder, store: store, preferences: preferences))
        host.appearance = NSAppearance(named: .aqua)
        host.frame = NSRect(x: 0, y: 0, width: 916, height: 510)
        let window = NSWindow(
            contentRect: host.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false)
        window.contentView = host
        window.orderFrontRegardless()
        defer {
            window.orderOut(nil)
            window.contentView = nil
        }
        try await Task.sleep(for: .milliseconds(700))

        var runs: [WidthAnimationRun] = []
        for scenario in ["sidebar-width", "inspector"] {
            model.width = scenario == "sidebar-width" ? 916 : 716
            try await Task.sleep(for: .milliseconds(500))
            for iteration in 0...30 {
                for compact in [true, false] {
                    let startWidth = try XCTUnwrap(recorder.view).frame.width
                    let targetWidth: CGFloat =
                        scenario == "sidebar-width"
                        ? (compact ? 716 : 916) : (compact ? 456 : 716)
                    recorder.begin()
                    let startedAt = ProcessInfo.processInfo.systemUptime
                    if scenario == "sidebar-width" {
                        withAnimation(DesignMotion.sidebar) { model.width = targetWidth }
                    } else {
                        model.isInspectorPresented = compact
                    }
                    var ticks: [Double] = []
                    while ProcessInfo.processInfo.systemUptime - startedAt < 0.48 {
                        try await Task.sleep(for: .milliseconds(1))
                        ticks.append(ProcessInfo.processInfo.systemUptime)
                    }
                    let updates = recorder.end()
                    let run = WidthAnimationRun(
                        scenario: scenario,
                        direction: compact ? "shrink" : "expand",
                        iteration: iteration,
                        startedAt: startedAt,
                        startWidth: startWidth,
                        targetWidth: targetWidth,
                        updates: updates,
                        ticks: ticks)
                    XCTAssertEqual(recorder.view?.frame.width ?? 0, targetWidth, accuracy: 1)
                    XCTAssertGreaterThan(
                        run.widthUpdates.count, 2,
                        "The diagnostic must observe intermediate width updates, not a final snap.")
                    if iteration > 0 { runs.append(run) }
                }
            }
        }
        XCTAssertEqual(recorder.makeCount, 1, "Animation must preserve workspace identity.")
        let shutdownFailure = await store.shutdown()
        XCTAssertNil(shutdownFailure)

        let report = WidthAnimationReport(
            operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
            instrumentCount: instruments.count,
            samplesPerDirection: 30,
            runs: runs)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(report)
        let reportURL = URL(fileURLWithPath: reportPath)
        try FileManager.default.createDirectory(
            at: reportURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: reportURL)
        print("ANIMATION_PERFORMANCE_REPORT \(reportPath)")
        for scenario in ["sidebar-width", "inspector"] {
            for direction in ["shrink", "expand"] {
                let matching = runs.filter { $0.scenario == scenario && $0.direction == direction }
                let updateGaps = Distribution(matching.flatMap(\.widthUpdateGapsMilliseconds))
                let runLoopGaps = Distribution(matching.flatMap(\.mainActorGapsMilliseconds))
                print(
                    "ANIMATION_PERFORMANCE \(scenario) \(direction) "
                        + "width_update_gap_ms=\(updateGaps) main_actor_gap_ms=\(runLoopGaps)")
            }
        }
    }

    private static func snapshot(for instrument: Instrument) throws -> QuoteSnapshot {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = instrument.market.timeZone
        let start = try XCTUnwrap(
            calendar.date(
                from: DateComponents(year: 2026, month: 9, day: 11, hour: 9, minute: 30)))
        let bars = (0..<240).map { index in
            let price = 100 + sin(Double(index) / 11) * 0.7 + Double(index) / 120
            return MinuteBar(
                time: start.addingTimeInterval(Double(index) * 60),
                open: price, close: price + 0.04, high: price + 0.1, low: price - 0.1)
        }
        return QuoteSnapshot(
            instrumentID: instrument.id,
            minuteBars: bars,
            dayOpen: bars[0].open,
            previousClose: 100,
            lastPrice: bars[bars.count - 1].close,
            marketTime: bars[bars.count - 1].time,
            receivedAt: bars[bars.count - 1].time.addingTimeInterval(1),
            source: .tencent)
    }
}

@MainActor
private final class WidthAnimationModel: ObservableObject {
    @Published var width: CGFloat = 916
    @Published var isInspectorPresented = false
}

@MainActor
private struct WidthAnimationHarness: View {
    @ObservedObject var model: WidthAnimationModel
    let recorder: WidthAnimationRecorder
    let store: MonitorStore
    let preferences: StockWatchPreferences

    var body: some View {
        StockWatchWorkspaceView(
            store: store, preferences: preferences,
            copyText: { _ in true }, revealDirectory: { _ in true }
        )
        .overlay { WidthAnimationProbe(recorder: recorder).allowsHitTesting(false) }
        // The workspace's own inspector stays uninstalled; this binding lets the diagnostic
        // drive the shared presentation while retaining the actual primary and inspector views.
        .toolInspector(
            isPresented: $model.isInspectorPresented,
            title: "标的与提醒",
            closeLabel: "关闭检查器"
        ) {
            StockWatchInspector(
                store: store,
                preferences: preferences,
                selectedInstrumentID: store.watchlistPresentation.instruments.first?.id,
                copyText: { _ in true }, revealDirectory: { _ in true })
        }
        .frame(width: model.width, height: 510)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .font(DesignTypography.body)
        .foregroundStyle(DesignPalette.light.textPrimary)
        .tint(DesignPalette.light.accent)
        .environment(\.colorScheme, .light)
        .environment(\.oneBoxAccessibilityReduceMotionOverride, false)
        .background(DesignPalette.light.background)
    }
}

@MainActor
private final class WidthAnimationRecorder {
    weak var view: WidthAnimationProbeView?
    var makeCount = 0
    private var isRecording = false
    private var updates: [WidthUpdate] = []

    func begin() {
        updates.removeAll(keepingCapacity: true)
        isRecording = true
    }

    func record(width: CGFloat) {
        guard isRecording, updates.last?.width != width else { return }
        updates.append(WidthUpdate(time: ProcessInfo.processInfo.systemUptime, width: width))
    }

    func end() -> [WidthUpdate] {
        isRecording = false
        return updates
    }
}

@MainActor
private struct WidthAnimationProbe: NSViewRepresentable {
    let recorder: WidthAnimationRecorder

    func makeNSView(context: Context) -> WidthAnimationProbeView {
        let view = WidthAnimationProbeView()
        view.recorder = recorder
        recorder.view = view
        recorder.makeCount += 1
        return view
    }

    func updateNSView(_ nsView: WidthAnimationProbeView, context: Context) {}
}

@MainActor
private final class WidthAnimationProbeView: NSView {
    weak var recorder: WidthAnimationRecorder?

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        recorder?.record(width: newSize.width)
    }
}

private struct WidthUpdate: Encodable {
    let time: Double
    let width: CGFloat
}

private struct WidthAnimationRun: Encodable {
    let scenario: String
    let direction: String
    let iteration: Int
    let firstChangeMilliseconds: Double?
    let sizingUpdateCount: Int
    let intermediateSizingUpdateCount: Int
    let widthUpdates: [WidthUpdate]
    let widthUpdateGapsMilliseconds: [Double]
    let widthStepsPoints: [Double]
    let mainActorGapsMilliseconds: [Double]

    init(
        scenario: String, direction: String, iteration: Int, startedAt: Double,
        startWidth: CGFloat, targetWidth: CGFloat,
        updates: [WidthUpdate], ticks: [Double]
    ) {
        self.scenario = scenario
        self.direction = direction
        self.iteration = iteration
        sizingUpdateCount = updates.count
        firstChangeMilliseconds = updates.first.map { ($0.time - startedAt) * 1_000 }
        // Exclude start/end plateaus and the final subpixel tail of the timing curve.
        let active = updates.filter {
            abs($0.width - startWidth) > 0.5 && abs($0.width - targetWidth) > 0.5
        }
        intermediateSizingUpdateCount = active.count
        widthUpdates = active.map {
            WidthUpdate(time: $0.time - startedAt, width: $0.width)
        }
        widthUpdateGapsMilliseconds = zip(active, active.dropFirst()).map {
            ($1.time - $0.time) * 1_000
        }
        widthStepsPoints = zip(active, active.dropFirst()).map { abs($1.width - $0.width) }
        if let first = active.first, let last = active.last {
            let activeTicks = ticks.filter { $0 >= first.time && $0 <= last.time }
            mainActorGapsMilliseconds = zip(activeTicks, activeTicks.dropFirst()).map {
                ($1 - $0) * 1_000
            }
        } else {
            mainActorGapsMilliseconds = []
        }
    }
}

private struct WidthAnimationReport: Encodable {
    let measurement = "NSView width-update delivery; not display presentation FPS"
    let operatingSystem: String
    let instrumentCount: Int
    let samplesPerDirection: Int
    let runs: [WidthAnimationRun]
}

private struct Distribution: CustomStringConvertible {
    let median: Double
    let p95: Double
    let maximum: Double

    init(_ samples: [Double]) {
        let sorted = samples.sorted()
        if sorted.isEmpty {
            median = 0
            p95 = 0
            maximum = 0
        } else {
            let middle = sorted.count / 2
            median =
                sorted.count.isMultiple(of: 2)
                ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
            p95 = sorted[max(0, Int(ceil(Double(sorted.count) * 0.95)) - 1)]
            maximum = sorted[sorted.count - 1]
        }
    }

    var description: String {
        String(format: "median:%.3f,p95:%.3f,max:%.3f", median, p95, maximum)
    }
}

private struct AnimationPerformanceMarketDataClient: MarketDataClient {
    let snapshots: [InstrumentID: QuoteSnapshot]

    func searchInstruments(matching query: String) async throws -> [Instrument] { [] }

    func fetchQuote(for instrument: Instrument) async throws -> QuoteSnapshot {
        guard let snapshot = snapshots[instrument.id] else {
            throw URLError(.resourceUnavailable)
        }
        return snapshot
    }
}
