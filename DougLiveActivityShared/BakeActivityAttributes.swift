import ActivityKit
import Foundation

struct BakeActivityAttributes: ActivityAttributes {
    let recipeName: String
    let recipeID: String

    struct ContentState: Codable, Hashable {
        let currentStepLabel: String
        let currentStepIcon: String
        let currentStepClassification: String
        let stepEndTime: Date
        let stepStartTime: Date

        let nextStepLabel: String?
        let nextStepStartTime: Date?

        /// Next pending sub-step within the current step (stretch & fold or
        /// add inclusions during bulk ferment, covered/uncovered phases during
        /// bake). When set, the countdown timer targets this instead of the
        /// step end.
        let nextFoldLabel: String?
        /// When the baker is next needed for that sub-step: its start when it
        /// hasn't begun (a pending fold), its end when it's already running
        /// (an active bake phase).
        let nextFoldTime: Date?
        /// True when the sub-step is underway — the countdown then reads as
        /// time remaining rather than time until it begins.
        let nextFoldIsRunning: Bool
        /// Identity of the sub-step, for intents acting on it from the widget.
        let nextFoldStepTypeID: String?
        let nextFoldSequenceIndex: Int?
        /// Button label for completing the sub-step from the Live Activity
        /// ("Lid Removed", "Bread Out"). Only set when the sub-step can be
        /// completed without any in-app data entry — folds want a dough
        /// temperature reading, so they direct into the app instead.
        let nextFoldActionLabel: String?

        /// The moment the countdown should target: the next fold if one is
        /// pending, otherwise the end of the current step.
        var timerTarget: Date {
            nextFoldTime ?? stepEndTime
        }

        /// Interval for a clamped countdown (`Text(timerInterval:)`): runs
        /// from the step start to the timer target and holds at 0:00 once it
        /// passes, instead of counting back up.
        var timerInterval: ClosedRange<Date> {
            min(stepStartTime, timerTarget) ... timerTarget
        }

        let completedStepCount: Int
        let totalStepCount: Int
        let breadReadyTime: Date

        let isPaused: Bool
        let isOverdue: Bool
    }
}
