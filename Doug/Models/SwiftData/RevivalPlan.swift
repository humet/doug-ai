import Foundation
import SwiftData

@Model
final class RevivalPlan {
    var status: String
    var startDate: Date
    var estimatedBakeReadyDate: Date?

    var initialStarterGrams: Double?
    var flourType: String?
    var kitchenTemperatureCelsius: Double?
    var currentStepIndex: Int = 0
    var assessedNeglect: String?
    var hadHooch: Bool = false
    var daysSinceLastFed: Int?
    var userNotes: String?
    var coachOpeningRead: String?

    @Relationship(deleteRule: .cascade, inverse: \RevivalFeedStep.plan)
    var feedSteps: [RevivalFeedStep] = []

    init() {
        status = RevivalStatus.active.rawValue
        startDate = Date()
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

    var retainStarterGrams: Double?
    var addFlourGrams: Double?
    var addWaterGrams: Double?
    var startedAt: Date?
    var peakTimestamp: Date?
    var timeToPeakMinutes: Double?
    var minPeakMinutes: Double?
    var maxPeakMinutes: Double?
    var originalScheduledTime: Date?

    var instructionTitle: String?
    var instructionBody: String?
    var instructionWatchFor: String?
    var instructionExpectedWait: String?

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
        status = RevivalFeedStatus.pending.rawValue
    }

    var feedStatus: RevivalFeedStatus {
        get { RevivalFeedStatus(rawValue: status) ?? .pending }
        set { status = newValue.rawValue }
    }
}

enum RevivalStatus: String, Codable {
    case active
    case completed
    case cancelled
}

enum RevivalFeedStatus: String, Codable {
    case pending
    case inProgress
    case completed
}
