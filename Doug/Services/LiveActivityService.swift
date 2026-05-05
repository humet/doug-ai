import ActivityKit
import Foundation

@MainActor
final class LiveActivityService {
    static let shared = LiveActivityService()

    private var currentBakeActivity: Activity<BakeActivityAttributes>?
    private var currentRevivalActivity: Activity<RevivalActivityAttributes>?

    private init() {}

    // MARK: - Bake Activities

    var hasBakeActivity: Bool {
        currentBakeActivity != nil
    }

    func startBakeActivity(recipeName: String, recipeID: String, state: BakeActivityAttributes.ContentState) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attributes = BakeActivityAttributes(recipeName: recipeName, recipeID: recipeID)
        let content = ActivityContent(state: state, staleDate: state.stepEndTime.addingTimeInterval(300))
        do {
            currentBakeActivity = try Activity.request(attributes: attributes, content: content)
        } catch {
            print("Failed to start bake Live Activity: \(error)")
        }
    }

    func updateBakeActivity(state: BakeActivityAttributes.ContentState) {
        guard let activity = currentBakeActivity else { return }
        let content = ActivityContent(state: state, staleDate: state.stepEndTime.addingTimeInterval(300))
        Task {
            await activity.update(content)
        }
    }

    func endBakeActivity(policy: ActivityUIDismissalPolicy = .default) {
        guard let activity = currentBakeActivity else { return }
        currentBakeActivity = nil
        Task {
            await activity.end(nil, dismissalPolicy: policy)
        }
    }

    func endBakeActivityImmediately() {
        endBakeActivity(policy: .immediate)
    }

    // MARK: - Revival Activities

    var hasRevivalActivity: Bool {
        currentRevivalActivity != nil
    }

    func startRevivalActivity(planStartDate: Date, state: RevivalActivityAttributes.ContentState) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attributes = RevivalActivityAttributes(planStartDate: planStartDate)
        let staleDate: Date? = state.scheduledMixTime ?? state.expectedPeakTime
        let content = ActivityContent(state: state, staleDate: staleDate?.addingTimeInterval(300))
        do {
            currentRevivalActivity = try Activity.request(attributes: attributes, content: content)
        } catch {
            print("Failed to start revival Live Activity: \(error)")
        }
    }

    func updateRevivalActivity(state: RevivalActivityAttributes.ContentState) {
        guard let activity = currentRevivalActivity else { return }
        let staleDate: Date? = state.scheduledMixTime ?? state.expectedPeakTime
        let content = ActivityContent(state: state, staleDate: staleDate?.addingTimeInterval(300))
        Task {
            await activity.update(content)
        }
    }

    func endRevivalActivity(policy: ActivityUIDismissalPolicy = .default) {
        guard let activity = currentRevivalActivity else { return }
        currentRevivalActivity = nil
        Task {
            await activity.end(nil, dismissalPolicy: policy)
        }
    }

    // MARK: - State Builders

    static func buildBakeState(from schedule: Schedule) -> BakeActivityAttributes.ContentState {
        let steps = schedule.steps
            .filter { $0.parentStep == nil }
            .sorted { $0.sequenceIndex < $1.sequenceIndex }

        let now = Date()
        let activeStep = steps.first { $0.stepStatus == .active }
        let completedCount = steps.filter { $0.stepStatus == .done || $0.stepStatus == .skipped }.count

        let currentStep = activeStep ?? steps.first { $0.stepStatus == .upcoming } ?? steps.last!
        let stepTypeID = StepTypeID(rawValue: currentStep.stepTypeID) ?? .mix
        let stepType = StepTypeRegistry.type(for: stepTypeID)

        let nextStep: ScheduleStep? = {
            guard let idx = steps.firstIndex(where: { $0 === currentStep }) else { return nil }
            let nextIdx = steps.index(after: idx)
            guard nextIdx < steps.endIndex else { return nil }
            return steps[nextIdx]
        }()

        let isOverdue = currentStep.stepStatus == .active && currentStep.computedEndTime < now

        return BakeActivityAttributes.ContentState(
            currentStepLabel: stepType.label,
            currentStepIcon: StepTypeIcon.systemName(for: stepTypeID),
            currentStepClassification: stepType.classification.rawValue,
            stepEndTime: currentStep.computedEndTime,
            stepStartTime: currentStep.computedStartTime,
            nextStepLabel: nextStep.map { StepTypeRegistry.type(for: StepTypeID(rawValue: $0.stepTypeID)!).label },
            nextStepStartTime: nextStep?.computedStartTime,
            completedStepCount: completedCount,
            totalStepCount: steps.count,
            breadReadyTime: schedule.targetBreadReadyTime,
            isPaused: schedule.pausedAt != nil,
            isOverdue: isOverdue
        )
    }

    static func buildRevivalState(from plan: RevivalPlan) -> RevivalActivityAttributes.ContentState {
        let steps = plan.feedSteps.sorted { $0.sequenceIndex < $1.sequenceIndex }
        let totalSteps = steps.count
        let currentIndex = plan.currentStepIndex

        guard currentIndex < totalSteps, let currentFeed = steps.first(where: { $0.sequenceIndex == currentIndex }) else {
            return RevivalActivityAttributes.ContentState(
                feedLabel: "Revival Complete",
                feedStatus: RevivalFeedStatus.completed.rawValue,
                scheduledMixTime: nil,
                risingStartTime: nil,
                expectedPeakTime: nil,
                minPeakTime: nil,
                maxPeakTime: nil,
                currentStepIndex: currentIndex,
                totalSteps: totalSteps,
                estimatedBakeReadyDate: plan.estimatedBakeReadyDate
            )
        }

        let feedLabel = "Feed \(currentIndex + 1)/\(totalSteps)"
        let status = currentFeed.feedStatus

        var expectedPeakTime: Date?
        var minPeakTime: Date?
        var maxPeakTime: Date?
        if let startedAt = currentFeed.startedAt {
            expectedPeakTime = startedAt.addingTimeInterval(currentFeed.expectedPeakMinutes * 60)
            if let minMin = currentFeed.minPeakMinutes {
                minPeakTime = startedAt.addingTimeInterval(minMin * 60)
            }
            if let maxMin = currentFeed.maxPeakMinutes {
                maxPeakTime = startedAt.addingTimeInterval(maxMin * 60)
            }
        }

        return RevivalActivityAttributes.ContentState(
            feedLabel: feedLabel,
            feedStatus: status.rawValue,
            scheduledMixTime: status == .pending ? currentFeed.scheduledTime : nil,
            risingStartTime: currentFeed.startedAt,
            expectedPeakTime: expectedPeakTime,
            minPeakTime: minPeakTime,
            maxPeakTime: maxPeakTime,
            currentStepIndex: currentIndex,
            totalSteps: totalSteps,
            estimatedBakeReadyDate: plan.estimatedBakeReadyDate
        )
    }

    // MARK: - Launch Reconciliation

    func reconcileOnLaunch(activeSchedule: Schedule?, activeRevivalPlan: RevivalPlan?) {
        reconcileBakeActivities(activeSchedule: activeSchedule)
        reconcileRevivalActivities(activeRevivalPlan: activeRevivalPlan)
    }

    private func reconcileBakeActivities(activeSchedule: Schedule?) {
        let existing = Activity<BakeActivityAttributes>.activities
        guard let schedule = activeSchedule else {
            for activity in existing {
                Task { await activity.end(nil, dismissalPolicy: .immediate) }
            }
            currentBakeActivity = nil
            return
        }

        let activeStep = schedule.steps
            .filter { $0.parentStep == nil }
            .first { $0.stepStatus == .active }
        let isColdRetard = activeStep.flatMap { StepTypeID(rawValue: $0.stepTypeID) } == .coldRetard

        if isColdRetard {
            for activity in existing {
                Task { await activity.end(nil, dismissalPolicy: .immediate) }
            }
            currentBakeActivity = nil
        } else if let activity = existing.first {
            currentBakeActivity = activity
            updateBakeActivity(state: Self.buildBakeState(from: schedule))
        } else {
            let state = Self.buildBakeState(from: schedule)
            startBakeActivity(
                recipeName: schedule.recipe.name,
                recipeID: schedule.recipeID,
                state: state
            )
        }
    }

    private func reconcileRevivalActivities(activeRevivalPlan: RevivalPlan?) {
        let existing = Activity<RevivalActivityAttributes>.activities
        guard let plan = activeRevivalPlan, plan.revivalStatus == .active else {
            for activity in existing {
                Task { await activity.end(nil, dismissalPolicy: .immediate) }
            }
            currentRevivalActivity = nil
            return
        }

        if let activity = existing.first {
            currentRevivalActivity = activity
            updateRevivalActivity(state: Self.buildRevivalState(from: plan))
        } else {
            let state = Self.buildRevivalState(from: plan)
            startRevivalActivity(planStartDate: plan.startDate, state: state)
        }
    }
}
