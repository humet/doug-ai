import Foundation
import SwiftData

@Model
final class RevivalPlan {
    var status: String
    var startDate: Date
    var estimatedBakeReadyDate: Date?

    @Relationship(deleteRule: .cascade, inverse: \RevivalFeedStep.plan)
    var feedSteps: [RevivalFeedStep] = []

    init() {
        self.status = RevivalStatus.active.rawValue
        self.startDate = Date()
    }

    var revivalStatus: RevivalStatus {
        get { RevivalStatus(rawValue: status) ?? .active }
        set { status = newValue.rawValue }
    }
}

@Model
final class RevivalFeedStep {
    var plan: RevivalPlan?
    var sequenceIndex: Int
    var targetRatioStarter: Int
    var targetRatioFlour: Int
    var targetRatioWater: Int
    var scheduledTime: Date
    var expectedPeakMinutes: Double
    var status: String
    var notificationIdentifier: String?

    init(
        sequenceIndex: Int,
        scheduledTime: Date,
        expectedPeakMinutes: Double,
        targetRatioStarter: Int = 1,
        targetRatioFlour: Int = 2,
        targetRatioWater: Int = 2
    ) {
        self.sequenceIndex = sequenceIndex
        self.scheduledTime = scheduledTime
        self.expectedPeakMinutes = expectedPeakMinutes
        self.targetRatioStarter = targetRatioStarter
        self.targetRatioFlour = targetRatioFlour
        self.targetRatioWater = targetRatioWater
        self.status = RevivalFeedStatus.pending.rawValue
    }

    var feedStatus: RevivalFeedStatus {
        get { RevivalFeedStatus(rawValue: status) ?? .pending }
        set { status = newValue.rawValue }
    }
}

enum RevivalStatus: String, Codable, Sendable {
    case active
    case completed
    case cancelled
}

enum RevivalFeedStatus: String, Codable, Sendable {
    case pending
    case completed
}
