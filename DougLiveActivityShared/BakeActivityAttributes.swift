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
        /// add inclusions during bulk ferment). When set, the countdown timer
        /// targets this instead of the step end.
        let nextFoldLabel: String?
        let nextFoldTime: Date?

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
