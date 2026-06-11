import ActivityKit
import Foundation

@MainActor
final class LiveActivityService {
    static let shared = LiveActivityService()

    private var currentBakeActivity: Activity<BakeActivityAttributes>?
    private var currentRevivalActivity: Activity<RevivalActivityAttributes>?

    // Updates chain behind the previous one — concurrent pushes to the same
    // activity can otherwise land out of order and leave stale content showing.
    private var bakeUpdateTask: Task<Void, Never>?
    private var revivalUpdateTask: Task<Void, Never>?

    private init() {}

    // MARK: - Bake Activities

    var hasBakeActivity: Bool {
        currentBakeActivity != nil
    }

    /// Five minutes past the countdown target the widget flips to its stale
    /// "due — open Doug" rendering. Never in the past: a state pushed when the
    /// target has already slipped is still fresh and should render as overdue,
    /// not stale.
    private static func bakeStaleDate(for state: BakeActivityAttributes.ContentState) -> Date {
        max(state.timerTarget, Date()).addingTimeInterval(300)
    }

    func startBakeActivity(recipeName: String, recipeID: String, state: BakeActivityAttributes.ContentState) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        // Live Activities outlive the process, but `currentBakeActivity` doesn't.
        // A start request issued before launch reconciliation runs must adopt the
        // surviving activity — requesting a second one leaves the old one frozen
        // on the lock screen with a stale step and a dead countdown.
        if let survivor = adoptSoleBakeActivity() {
            currentBakeActivity = survivor
            updateBakeActivity(state: state)
            return
        }
        let attributes = BakeActivityAttributes(recipeName: recipeName, recipeID: recipeID)
        let content = ActivityContent(state: state, staleDate: Self.bakeStaleDate(for: state))
        do {
            currentBakeActivity = try Activity.request(attributes: attributes, content: content)
        } catch {
            print("Failed to start bake Live Activity: \(error)")
        }
    }

    /// Picks one surviving system activity (preferring the already-tracked one)
    /// and ends every other — the app never wants more than one bake activity.
    private func adoptSoleBakeActivity() -> Activity<BakeActivityAttributes>? {
        let existing = Activity<BakeActivityAttributes>.activities
        guard let adopted = existing.first(where: { $0.id == currentBakeActivity?.id }) ?? existing.first
        else { return nil }
        for extra in existing where extra.id != adopted.id {
            Task { await extra.end(nil, dismissalPolicy: .immediate) }
        }
        return adopted
    }

    func updateBakeActivity(state: BakeActivityAttributes.ContentState) {
        guard let activity = currentBakeActivity else { return }
        let content = ActivityContent(state: state, staleDate: Self.bakeStaleDate(for: state))
        let previous = bakeUpdateTask
        bakeUpdateTask = Task {
            await previous?.value
            await activity.update(content)
        }
    }

    func endBakeActivity(policy: ActivityUIDismissalPolicy = .immediate) {
        currentBakeActivity = nil
        // End every system activity, not just the tracked one — an activity
        // from a previous process is otherwise stranded past the bake's end.
        for activity in Activity<BakeActivityAttributes>.activities {
            Task { await activity.end(nil, dismissalPolicy: policy) }
        }
    }

    // MARK: - Revival Activities

    var hasRevivalActivity: Bool {
        currentRevivalActivity != nil
    }

    func startRevivalActivity(planStartDate: Date, state: RevivalActivityAttributes.ContentState) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        // Same adoption rule as the bake activity: never request a duplicate
        // when one survived the previous process.
        if let survivor = adoptSoleRevivalActivity() {
            currentRevivalActivity = survivor
            updateRevivalActivity(state: state)
            return
        }
        let attributes = RevivalActivityAttributes(planStartDate: planStartDate)
        let staleDate: Date? = state.scheduledMixTime ?? state.expectedPeakTime
        let content = ActivityContent(state: state, staleDate: staleDate?.addingTimeInterval(300))
        do {
            currentRevivalActivity = try Activity.request(attributes: attributes, content: content)
        } catch {
            print("Failed to start revival Live Activity: \(error)")
        }
    }

    private func adoptSoleRevivalActivity() -> Activity<RevivalActivityAttributes>? {
        let existing = Activity<RevivalActivityAttributes>.activities
        guard let adopted = existing.first(where: { $0.id == currentRevivalActivity?.id }) ?? existing.first
        else { return nil }
        for extra in existing where extra.id != adopted.id {
            Task { await extra.end(nil, dismissalPolicy: .immediate) }
        }
        return adopted
    }

    func updateRevivalActivity(state: RevivalActivityAttributes.ContentState) {
        guard let activity = currentRevivalActivity else { return }
        let staleDate: Date? = state.scheduledMixTime ?? state.expectedPeakTime
        let content = ActivityContent(state: state, staleDate: staleDate?.addingTimeInterval(300))
        let previous = revivalUpdateTask
        revivalUpdateTask = Task {
            await previous?.value
            await activity.update(content)
        }
    }

    func endRevivalActivity(policy: ActivityUIDismissalPolicy = .immediate) {
        currentRevivalActivity = nil
        for activity in Activity<RevivalActivityAttributes>.activities {
            Task { await activity.end(nil, dismissalPolicy: policy) }
        }
    }

    // MARK: - Visibility Policy

    /// Step types worth a Live Activity — passive waits where the lock screen
    /// countdown is the interface.
    private static let liveActivitySteps: Set<String> = [
        StepTypeID.autolyse.rawValue,
        StepTypeID.bulkFerment.rawValue,
        StepTypeID.coldRetard.rawValue,
        StepTypeID.finalProof.rawValue,
        StepTypeID.preheat.rawValue,
        StepTypeID.bake.rawValue,
        StepTypeID.bakeSheet.rawValue,
        StepTypeID.waitForPeak.rawValue,
        StepTypeID.waitForLevainPeak.rawValue,
    ]

    /// Long waits only get an activity inside the final hour — an all-night
    /// countdown is noise.
    private static let liveActivityLongWaitSteps: Set<String> = [
        StepTypeID.waitForPeak.rawValue,
        StepTypeID.waitForLevainPeak.rawValue,
        StepTypeID.coldRetard.rawValue,
    ]

    private static let liveActivityResumeThreshold: TimeInterval = 60 * 60

    /// Single source of truth for whether the schedule warrants a bake activity
    /// right now — `syncLiveActivity` and launch reconciliation must agree, or
    /// whichever runs second undoes the other.
    static func shouldShowBakeActivity(for schedule: Schedule, now: Date = Date()) -> Bool {
        guard schedule.scheduleStatus == .active else { return false }
        let activeStep = schedule.steps
            .filter { $0.parentStep == nil }
            .first { $0.stepStatus == .active }
        guard let active = activeStep else { return true }
        guard liveActivitySteps.contains(active.stepTypeID) else { return false }
        guard liveActivityLongWaitSteps.contains(active.stepTypeID) else { return true }
        return active.computedEndTime.timeIntervalSince(now) <= liveActivityResumeThreshold
    }

    // MARK: - State Builders

    static func buildBakeState(from schedule: Schedule) -> BakeActivityAttributes.ContentState {
        let steps = schedule.steps
            .filter { $0.parentStep == nil }
            .sorted { $0.sequenceIndex < $1.sequenceIndex }

        let now = Date()
        let activeStep = steps.first { $0.stepStatus == .active }
        let completedCount = steps.count(where: { $0.stepStatus == .done || $0.stepStatus == .skipped })

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

        // During steps with sub-steps, the next pending sub-step is the moment
        // the baker actually needs — count down to it rather than to the end
        // of the whole step.
        let nextFold: ScheduleStep? = currentStep.stepStatus == .active
            ? currentStep.subSteps
            .sorted { $0.sequenceIndex < $1.sequenceIndex }
            .first { $0.stepStatus != .done && $0.stepStatus != .skipped }
            : nil

        // A fold is an instant the baker waits for, so the countdown targets
        // its start. A bake phase runs (`.active`) — counting down to its
        // start would pin the timer at 0:00; the baker needs its end.
        let nextFoldIsRunning = nextFold?.stepStatus == .active
        let nextFoldTarget = nextFold.map { nextFoldIsRunning ? $0.computedEndTime : $0.computedStartTime }

        // Running bake phases complete with one confirmation and no data
        // entry, so they get a button on the activity itself. Folds want a
        // dough temperature reading and keep directing into the app.
        let nextFoldActionLabel: String? = {
            guard nextFoldIsRunning else { return nil }
            switch nextFold.flatMap({ StepTypeID(rawValue: $0.stepTypeID) }) {
            case .bakeCovered: return "Lid Removed"
            case .bakeUncovered: return "Bread Out"
            default: return nil
            }
        }()

        return BakeActivityAttributes.ContentState(
            currentStepLabel: stepType.label,
            currentStepIcon: StepTypeIcon.systemName(for: stepTypeID),
            currentStepClassification: stepType.classification.rawValue,
            stepEndTime: currentStep.computedEndTime,
            stepStartTime: currentStep.computedStartTime,
            nextStepLabel: nextStep.map { StepTypeRegistry.type(for: StepTypeID(rawValue: $0.stepTypeID)!).label },
            nextStepStartTime: nextStep?.computedStartTime,
            nextFoldLabel: nextFold.flatMap { StepTypeID(rawValue: $0.stepTypeID) }
                .map { StepTypeRegistry.type(for: $0).label },
            nextFoldTime: nextFoldTarget,
            nextFoldIsRunning: nextFoldIsRunning,
            nextFoldStepTypeID: nextFold?.stepTypeID,
            nextFoldSequenceIndex: nextFold?.sequenceIndex,
            nextFoldActionLabel: nextFoldActionLabel,
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

        guard currentIndex < totalSteps,
              let currentFeed = steps.first(where: { $0.sequenceIndex == currentIndex })
        else {
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
        guard let schedule = activeSchedule, Self.shouldShowBakeActivity(for: schedule) else {
            endBakeActivity()
            return
        }

        if let activity = adoptSoleBakeActivity() {
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
        guard let plan = activeRevivalPlan, plan.revivalStatus == .active else {
            endRevivalActivity()
            return
        }

        if let activity = adoptSoleRevivalActivity() {
            currentRevivalActivity = activity
            updateRevivalActivity(state: Self.buildRevivalState(from: plan))
        } else {
            let state = Self.buildRevivalState(from: plan)
            startRevivalActivity(planStartDate: plan.startDate, state: state)
        }
    }
}
