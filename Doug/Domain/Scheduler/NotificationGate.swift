import Foundation

/// Decides how far ahead step notifications may be scheduled for an active bake.
///
/// Some steps end when the baker says they end, not when the clock does — a levain
/// peak or bulk fermentation is judged visually and routinely runs long or short of
/// its predicted duration. A notification scheduled beyond such a "gate" step fires
/// at a speculative time, nagging about steps that cannot have started yet. Local
/// notifications can't be adjusted while the app is backgrounded, so the only safe
/// policy is to never schedule past an unconfirmed gate; completing the gate
/// cascades the timeline and schedules the next stretch.
enum NotificationGate {
    /// Steps whose true duration is judged by the baker rather than the timer.
    static let gateStepTypeIDs: Set<String> = [
        StepTypeID.waitForPeak.rawValue,
        StepTypeID.waitForLevainPeak.rawValue,
        StepTypeID.bulkFerment.rawValue,
    ]

    static func isGate(stepTypeID: String) -> Bool {
        gateStepTypeIDs.contains(stepTypeID)
    }

    /// One top-level step as seen by the gate policy.
    struct StepInfo {
        let stepTypeID: String
        /// Upcoming or active — i.e. not yet confirmed done or skipped.
        let isPending: Bool

        init(stepTypeID: String, isPending: Bool) {
            self.stepTypeID = stepTypeID
            self.isPending = isPending
        }
    }

    /// Given the schedule's top-level steps in order, returns the index of the first
    /// pending gate, or nil when nothing gates scheduling. Steps after that index
    /// (and substeps of steps after it) must not have notifications scheduled yet;
    /// the gate itself and its own substeps may.
    static func firstPendingGateIndex(in steps: [StepInfo]) -> Int? {
        steps.firstIndex { $0.isPending && isGate(stepTypeID: $0.stepTypeID) }
    }
}
