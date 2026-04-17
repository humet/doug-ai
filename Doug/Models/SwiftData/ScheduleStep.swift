import Foundation
import SwiftData

@Model
final class ScheduleStep {
    var schedule: Schedule?
    var stepTypeID: String
    var sequenceIndex: Int
    var computedStartTime: Date
    var computedEndTime: Date
    var computedDurationMinutes: Double
    var status: String
    var notificationIdentifier: String?
    var actualEndTime: Date?

    var parentStep: ScheduleStep?
    @Relationship(deleteRule: .cascade, inverse: \ScheduleStep.parentStep)
    var subSteps: [ScheduleStep] = []

    init(
        stepTypeID: StepTypeID,
        sequenceIndex: Int,
        computedStartTime: Date,
        computedEndTime: Date,
        computedDurationMinutes: Double
    ) {
        self.stepTypeID = stepTypeID.rawValue
        self.sequenceIndex = sequenceIndex
        self.computedStartTime = computedStartTime
        self.computedEndTime = computedEndTime
        self.computedDurationMinutes = computedDurationMinutes
        status = StepStatus.upcoming.rawValue
    }

    var stepStatus: StepStatus {
        get { StepStatus(rawValue: status) ?? .upcoming }
        set { status = newValue.rawValue }
    }

    var stepType: StepType {
        StepTypeRegistry.type(for: StepTypeID(rawValue: stepTypeID)!)
    }
}

enum StepStatus: String, Codable {
    case upcoming
    case active
    case done
    case skipped
}
