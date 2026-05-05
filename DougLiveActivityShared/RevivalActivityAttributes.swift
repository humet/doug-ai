import ActivityKit
import Foundation

struct RevivalActivityAttributes: ActivityAttributes {
    let planStartDate: Date

    struct ContentState: Codable, Hashable {
        let feedLabel: String
        let feedStatus: String

        let scheduledMixTime: Date?

        let risingStartTime: Date?
        let expectedPeakTime: Date?
        let minPeakTime: Date?
        let maxPeakTime: Date?

        let currentStepIndex: Int
        let totalSteps: Int
        let estimatedBakeReadyDate: Date?
    }
}
