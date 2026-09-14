import AppKit
import SwiftUI
import XCTest

@testable import OneBoxDesignSystem

@MainActor
final class ToolSliderTests: XCTestCase {
    func testRepeatedKeysAdvanceFromPendingValueBeforePlaybackCatchesUp() async throws {
        let progress = DelayedPlaybackProgress()
        let host = NSHostingView(rootView: KeyboardSliderProbe(progress: progress))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 100),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer {
            window.orderOut(nil)
            window.contentView = nil
        }
        try await Task.sleep(for: .milliseconds(100))

        for keyCode: UInt16 in [124, 124, 124, 123] {
            let character = keyCode == 124 ? "\u{F703}" : "\u{F702}"
            let event = try XCTUnwrap(
                NSEvent.keyEvent(
                    with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                    windowNumber: window.windowNumber, context: nil, characters: character,
                    charactersIgnoringModifiers: character, isARepeat: false, keyCode: keyCode))
            window.sendEvent(event)
            try await Task.sleep(for: .milliseconds(30))
        }

        XCTAssertEqual(progress.seekTargets, [110, 120, 130, 120])
        XCTAssertEqual(
            progress.editingEvents, [true, false, true, false, true, false, true, false])
    }

    func testPointerMappingUsesTheWholeTrackAndClampsDragBeyondItsEnds() {
        let scale = ToolSliderScale(bounds: 5...20, step: 1)
        XCTAssertEqual(scale.value(at: 0, width: 200), 5)
        XCTAssertEqual(scale.value(at: 200, width: 200), 20)
        XCTAssertEqual(scale.value(at: -40, width: 200), 5)
        XCTAssertEqual(scale.value(at: 240, width: 200), 20)
        XCTAssertEqual(scale.fraction(for: 5), 0)
        XCTAssertEqual(scale.fraction(for: 20), 1)
        XCTAssertEqual(scale.fraction(for: 12.5), 0.5)
    }

    func testDiscretePointerValuesSnapRelativeToTheMinimum() {
        let scale = ToolSliderScale(bounds: 0.4...2, step: 0.05)
        XCTAssertEqual(scale.value(at: 55, width: 200), 0.85, accuracy: 0.000_001)
        XCTAssertEqual(scale.adjusting(0.85, by: 1), 0.9, accuracy: 0.000_001)
        XCTAssertEqual(scale.adjusting(0.85, by: -1), 0.8, accuracy: 0.000_001)
        XCTAssertEqual(scale.adjusting(0.85, by: 10), 1.35, accuracy: 0.000_001)
        XCTAssertEqual(scale.adjusting(2, by: 1), 2)
        XCTAssertEqual(scale.adjusting(0.4, by: -1), 0.4)
    }

    func testContinuousPointerValuesRemainSmoothWhileKeysMoveOnePercentOfRange() {
        let scale = ToolSliderScale(bounds: 0...1, step: nil)
        XCTAssertEqual(scale.value(at: 123.4, width: 200), 0.617, accuracy: 0.000_001)
        XCTAssertEqual(scale.adjusting(0.6, by: 1), 0.61, accuracy: 0.000_001)
        XCTAssertEqual(scale.adjusting(0.6, by: -1), 0.59, accuracy: 0.000_001)
        XCTAssertEqual(scale.adjusting(0.6, by: 10), 0.7, accuracy: 0.000_001)
        XCTAssertEqual(scale.adjusting(0.99, by: 10), 1)
    }

    func testSliderCanLayOutBeforeReceivingAWidth() {
        let scale = ToolSliderScale(bounds: 5...20, step: 1)
        XCTAssertEqual(scale.value(at: 0, width: 0), 5)
    }
}

/// Models PodPin's draft/optimistic binding while an asynchronous seek is still pending.
@MainActor
private final class DelayedPlaybackProgress: ObservableObject {
    @Published private var draftTime = 0.0
    @Published private var isScrubbing = false
    @Published private var optimisticTime: Double?
    private(set) var seekTargets: [Double] = []
    private(set) var editingEvents: [Bool] = []

    private var displayedTime: Double { isScrubbing ? draftTime : (optimisticTime ?? 100) }

    var value: Binding<Double> {
        Binding(
            get: { self.displayedTime },
            set: {
                self.draftTime = $0
                self.isScrubbing = true
            })
    }

    func editingChanged(_ editing: Bool) {
        editingEvents.append(editing)
        if editing {
            optimisticTime = nil
            draftTime = displayedTime
            isScrubbing = true
        } else {
            isScrubbing = false
            optimisticTime = draftTime
            seekTargets.append(draftTime)
        }
    }
}

@MainActor
private struct KeyboardSliderProbe: View {
    @ObservedObject var progress: DelayedPlaybackProgress
    @FocusState private var isFocused: Bool

    var body: some View {
        ToolSlider(
            "播放进度", value: progress.value, in: 0...1000,
            onEditingChanged: progress.editingChanged
        )
        .focused($isFocused)
        .padding(24)
        .onAppear { isFocused = true }
    }
}
