import Foundation

/// Pure decisions about which notifications are worth delivering.
enum NotificationPolicy {
    /// A passive-flexible step's "timer complete" notification is redundant when
    /// the immediately following step gets its own reminder 5 minutes before it
    /// starts — i.e. 5 minutes before this step ends. Suppress the completion
    /// notification for those pairs (autolyse → mix, cold retard → preheat,
    /// final proof → preheat) so the user gets one buzz, not two in confusing
    /// order.
    ///
    /// Accepted edge: if the next step's before-start reminder is itself skipped
    /// because its fire time has already passed, neither notification fires.
    static func shouldScheduleFlexibleCompletion(nextTopLevelStepTypeID: String?) -> Bool {
        guard let raw = nextTopLevelStepTypeID, let id = StepTypeID(rawValue: raw) else {
            return true
        }
        let nextType = StepTypeRegistry.type(for: id)
        // Mirrors the set of steps that receive a 5-min-before-start reminder
        // in NotificationService.scheduleNotifications.
        return !(nextType.classification == .handsOn || id == .preheat)
    }
}
