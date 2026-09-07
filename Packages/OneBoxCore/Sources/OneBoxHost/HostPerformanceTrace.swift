import OSLog
import OneBoxRuntime

@MainActor
final class HostPerformanceTrace {
    private struct PendingActivation {
        let toolID: ToolID
        var activation: OSSignpostIntervalState?
        var firstContent: OSSignpostIntervalState?
    }

    private static let signposter = OSSignposter(
        subsystem: "com.cmy.OneBox",
        category: "Host"
    )

    private var pending: PendingActivation?

    init(initialToolID: ToolID?) {
        guard let initialToolID else { return }
        beginActivation(for: initialToolID)
    }

    func beginActivation(for toolID: ToolID) {
        finishPendingActivation()
        pending = PendingActivation(
            toolID: toolID,
            activation: Self.signposter.beginInterval("ToolActivation"),
            firstContent: Self.signposter.beginInterval("FirstContentReady")
        )
    }

    func contentDidAppear(for toolID: ToolID) {
        guard var pending, pending.toolID == toolID,
            let activation = pending.activation
        else {
            return
        }
        Self.signposter.endInterval("ToolActivation", activation)
        pending.activation = nil
        storeIfIncomplete(pending)
    }

    @discardableResult
    func contentDidBecomeReady(for toolID: ToolID) -> Bool {
        guard var pending, pending.toolID == toolID,
            let firstContent = pending.firstContent
        else {
            return false
        }
        Self.signposter.endInterval("FirstContentReady", firstContent)
        pending.firstContent = nil
        storeIfIncomplete(pending)
        return true
    }

    private func finishPendingActivation() {
        guard let pending else { return }
        self.pending = nil
        if let firstContent = pending.firstContent {
            Self.signposter.endInterval(
                "FirstContentReady",
                firstContent,
                "cancelled"
            )
        }
        if let activation = pending.activation {
            Self.signposter.endInterval(
                "ToolActivation",
                activation,
                "cancelled"
            )
        }
    }

    private func storeIfIncomplete(_ pending: PendingActivation) {
        if pending.activation == nil, pending.firstContent == nil {
            self.pending = nil
        } else {
            self.pending = pending
        }
    }
}
