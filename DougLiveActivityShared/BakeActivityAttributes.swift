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

        let completedStepCount: Int
        let totalStepCount: Int
        let breadReadyTime: Date

        let isPaused: Bool
        let isOverdue: Bool
    }
}
