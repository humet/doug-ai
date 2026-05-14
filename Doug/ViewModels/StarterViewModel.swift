import Foundation
import Observation
import SwiftData

@Observable
@MainActor
final class StarterViewModel {
    var showLogFeed = false
    var showStartRevival = false
    var showPostBake = false
    var editingFeedLog: StarterFeedLog?

    // Feed entry form state
    var feedRatioStarter = 1
    var feedRatioFlour = 1
    var feedRatioWater = 1
    var feedFlourType = "white"
    var feedKitchenTemp = 22.0
    var feedTimestamp = Date()
    var logFeedStarterGrams = ""

    // Revival wizard form state
    var revivalDaysSinceLastFed: Int?
    var revivalHasHooch = false
    var revivalSmellsAcetone = false
    var revivalHasBubbles = false
    var revivalHasPinkOrangeOrMold = false
    var revivalNotes = ""
    var revivalStarterGrams = "20"
    var revivalFlourType = "white"
    var revivalKitchenTemp = 22.0
    var revivalIsPreparing = false

    func healthStatus(
        profile: StarterProfile?,
        feedLogs: [StarterFeedLog]
    ) -> StarterHealthStatus {
        guard let profile else { return .needsFeed }

        let profileInput = StarterProfileInput(from: profile)
        let logInputs = feedLogs.map { FeedLogInput(from: $0) }

        return StarterHealthAssessor.assess(
            profile: profileInput,
            feedLogs: logInputs
        )
    }

    func nextFeedTime(
        profile: StarterProfile?,
        feedLogs: [StarterFeedLog],
        availability: UserAvailability?,
        windows: [UnavailableWindow],
        upcomingBakeStart: Date?
    ) -> Date? {
        guard let profile else { return nil }

        let avail = availability.map { AvailabilityInput(from: $0) }
            ?? AvailabilityInput(startHour: 6, startMinute: 30, endHour: 21, endMinute: 0)

        return FeedScheduler.nextFeedTime(
            lastFeedTime: feedLogs.first?.timestamp,
            cycleDays: profile.maintenanceCycleDays,
            upcomingBakeStart: upcomingBakeStart,
            availability: avail,
            windows: windows.map { WindowInput(from: $0) }
        )
    }

    /// Human-readable context used as the notification body and the starter card subtitle.
    func feedContext(nextFeed _: Date, upcomingBakeStart: Date?) -> String {
        if upcomingBakeStart != nil {
            return "Feeding now keeps your starter lined up for your upcoming bake."
        }
        return "Keep your starter on a healthy maintenance rhythm."
    }

    /// Schedules (or replaces) the pending starter feed reminder for the given date.
    /// Call whenever the suggestion changes — on appear, after logging, after availability edits.
    func syncFeedReminder(nextFeed: Date?, upcomingBakeStart: Date?) async {
        guard let nextFeed else {
            NotificationService.shared.cancelStarterFeedReminder()
            return
        }
        let context = feedContext(nextFeed: nextFeed, upcomingBakeStart: upcomingBakeStart)
        await NotificationService.shared.scheduleStarterFeedReminder(at: nextFeed, context: context)
    }

    func logFeed(modelContext: ModelContext, profile: StarterProfile? = nil, intent: FeedIntent? = nil) {
        let resolvedIntent = intent ?? inferFeedIntent(profile: profile)
        let grams = Double(logFeedStarterGrams.trimmingCharacters(in: .whitespaces))
        let log = StarterFeedLog(
            timestamp: feedTimestamp,
            ratioStarter: feedRatioStarter,
            ratioFlour: feedRatioFlour,
            ratioWater: feedRatioWater,
            flourType: feedFlourType,
            kitchenTemperatureCelsius: feedKitchenTemp,
            starterGrams: grams,
            feedIntent: resolvedIntent
        )
        modelContext.insert(log)

        feedRatioStarter = 1
        feedRatioFlour = 2
        feedRatioWater = 2
        feedFlourType = "white"
        feedTimestamp = Date()
        logFeedStarterGrams = ""

        showLogFeed = false
    }

    private func inferFeedIntent(profile: StarterProfile?) -> FeedIntent {
        switch profile?.starterLifecycleState {
        case .activating: .activation
        case .active: .postBake
        default: .maintenance
        }
    }

    func deleteFeedLog(
        _ log: StarterFeedLog,
        modelContext: ModelContext,
        profile: StarterProfile?,
        feedLogs: [StarterFeedLog]
    ) {
        modelContext.delete(log)
        let remaining = feedLogs.filter { $0.persistentModelID != log.persistentModelID }
        updateProfileAverages(profile: profile, feedLogs: remaining)
    }

    func markPeak(for log: StarterFeedLog, profile: StarterProfile?, allLogs: [StarterFeedLog]) {
        log.markPeak(at: Date())
        updateProfileAverages(profile: profile, feedLogs: allLogs)

        if log.starterFeedIntent == .activation, let profile {
            evaluateLifecycle(profile: profile, feedLogs: allLogs)
        }
    }

    func updateProfileAverages(profile: StarterProfile?, feedLogs: [StarterFeedLog]) {
        guard let profile else { return }

        let allPeakTimes = feedLogs.compactMap(\.timeToPeakMinutes)
        if !allPeakTimes.isEmpty {
            profile.averageTimeToPeakMinutes = allPeakTimes.reduce(0, +) / Double(allPeakTimes.count)
        }

        let activationPeakTimes = feedLogs
            .filter { $0.starterFeedIntent == .activation }
            .compactMap(\.timeToPeakMinutes)
        if !activationPeakTimes.isEmpty {
            profile.activePeakAverageMinutes = activationPeakTimes.reduce(0, +) / Double(activationPeakTimes.count)
        }

        profile.starterHealthStatus = healthStatus(profile: profile, feedLogs: feedLogs)
        profile.lastUpdated = Date()
    }

    // MARK: - Lifecycle

    func activate(profile: StarterProfile) {
        if let result = StarterStateMachine.activate(currentState: profile.starterLifecycleState) {
            profile.starterLifecycleState = result.newState
            profile.starterStorageType = .counter
        }
    }

    func refrigerate(profile: StarterProfile) {
        if let result = StarterStateMachine.refrigerate(currentState: profile.starterLifecycleState) {
            profile.starterLifecycleState = result.newState
            profile.starterStorageType = .fridge
        }
    }

    func feedAndRefrigerate(profile: StarterProfile, modelContext: ModelContext) {
        logFeed(modelContext: modelContext, profile: profile, intent: .postBake)
        if let result = StarterStateMachine.refrigerate(currentState: profile.starterLifecycleState) {
            profile.starterLifecycleState = result.newState
            profile.starterStorageType = .fridge
        }
    }

    func evaluateLifecycle(profile: StarterProfile, feedLogs: [StarterFeedLog]) {
        let activationLogs = feedLogs.filter { $0.starterFeedIntent == .activation }
        let lastActivation = activationLogs.first.map { FeedLogInput(from: $0) }

        if let result = StarterStateMachine.evaluateAutoTransition(
            currentState: profile.starterLifecycleState,
            stateChangedAt: profile.stateChangedAt,
            lastActivationFeed: lastActivation,
            activePeakAverage: profile.activePeakAverageMinutes
        ) {
            profile.starterLifecycleState = result.newState
        }
    }

    func feedSuggestion(
        profile: StarterProfile?,
        feedLogs: [StarterFeedLog],
        availability: UserAvailability?,
        windows: [UnavailableWindow],
        upcomingBakeStart: Date?
    ) -> FeedSuggestion? {
        guard let profile else { return nil }

        let avail = availability.map { AvailabilityInput(from: $0) }
            ?? AvailabilityInput(startHour: 6, startMinute: 30, endHour: 21, endMinute: 0)

        return FeedScheduler.suggestNextFeed(
            lifecycleState: profile.starterLifecycleState,
            stateChangedAt: profile.stateChangedAt,
            lastFeedTime: feedLogs.first?.timestamp,
            cycleDays: profile.maintenanceCycleDays,
            upcomingBakeStart: upcomingBakeStart,
            activePeakAverage: profile.activePeakAverageMinutes,
            kitchenTempC: feedLogs.first?.kitchenTemperatureCelsius ?? 22,
            availability: avail,
            windows: windows.map { WindowInput(from: $0) }
        )
    }

    // MARK: - Revival

    /// Reads the current wizard form into a structured condition input for the assessor.
    var revivalConditionInput: StarterConditionInput {
        StarterConditionInput(
            daysSinceLastFed: revivalDaysSinceLastFed,
            hasHooch: revivalHasHooch,
            smellsStronglyAcetone: revivalSmellsAcetone,
            hasBubbles: revivalHasBubbles,
            hasPinkOrangeOrMold: revivalHasPinkOrangeOrMold
        )
    }

    /// Current safety verdict based on what the user has toggled, recomputed on every read.
    var revivalSafetyVerdict: StarterSafetyVerdict {
        StarterConditionAssessor.assess(revivalConditionInput)
    }

    /// Generates a revival plan using the wizard form state, assesses condition,
    /// writes grams + tolerance onto each step, and asks the LLM coach for copy.
    ///
    /// Returns nil if the verdict is `.discardAndRestart` (caller should show the safety card).
    func startRevival(
        startAt: Date? = nil,
        availability: UserAvailability?,
        windows: [UnavailableWindow],
        modelContext: ModelContext
    ) async -> RevivalPlan? {
        let verdict = revivalSafetyVerdict
        guard case let .safeToRevive(neglect) = verdict else {
            return nil
        }

        let grams = Double(revivalStarterGrams.trimmingCharacters(in: .whitespaces)) ?? 20
        let avail = availability.map { AvailabilityInput(from: $0) }
            ?? AvailabilityInput(startHour: 6, startMinute: 30, endHour: 21, endMinute: 0)
        let windowInputs = windows.map { WindowInput(from: $0) }
        let startTime = startAt ?? Date()

        let feedPlans = RevivalPlanGenerator.generate(
            startTime: startTime,
            initialStarterGrams: grams,
            neglect: neglect,
            kitchenTempC: revivalKitchenTemp,
            availability: avail,
            windows: windowInputs
        )

        let plan = RevivalPlan()
        plan.startDate = startTime
        plan.estimatedBakeReadyDate = RevivalPlanGenerator.estimatedBakeReadyDate(from: feedPlans)
        plan.initialStarterGrams = grams
        plan.flourType = revivalFlourType
        plan.kitchenTemperatureCelsius = revivalKitchenTemp
        plan.assessedNeglect = neglect.rawValue
        plan.hadHooch = revivalHasHooch
        plan.daysSinceLastFed = revivalDaysSinceLastFed
        let trimmedNotes = revivalNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        plan.userNotes = trimmedNotes.isEmpty ? nil : trimmedNotes
        modelContext.insert(plan)

        var stepsByIndex: [Int: RevivalFeedStep] = [:]
        let totalSteps = feedPlans.count
        for feedPlan in feedPlans {
            let step = RevivalFeedStep(
                sequenceIndex: feedPlan.sequenceIndex,
                scheduledTime: feedPlan.scheduledTime,
                expectedPeakMinutes: feedPlan.expectedPeakMinutes,
                targetRatioStarter: feedPlan.ratioStarter,
                targetRatioFlour: feedPlan.ratioFlour,
                targetRatioWater: feedPlan.ratioWater
            )
            step.plan = plan
            step.originalScheduledTime = feedPlan.scheduledTime
            step.retainStarterGrams = feedPlan.retainStarterGrams
            step.addFlourGrams = feedPlan.addFlourGrams
            step.addWaterGrams = feedPlan.addWaterGrams
            step.minPeakMinutes = feedPlan.minPeakMinutes
            step.maxPeakMinutes = feedPlan.maxPeakMinutes
            stepsByIndex[feedPlan.sequenceIndex] = step
        }

        applyFallbackInstructions(plan: plan, totalSteps: totalSteps)

        resetRevivalForm()
        syncRevivalActivity(plan: plan)
        scheduleNextRevivalReminder(plan: plan)
        return plan
    }

    /// Marks a revival step as mixed & rising. If the previous step was peaked,
    /// completes it and advances `currentStepIndex` so the new step becomes current.
    func markRevivalStepStarted(
        step: RevivalFeedStep,
        plan: RevivalPlan,
        availability: UserAvailability?,
        windows: [UnavailableWindow]
    ) {
        let sortedSteps = plan.feedSteps.sorted { $0.sequenceIndex < $1.sequenceIndex }
        if let previous = sortedSteps.first(where: { $0.sequenceIndex == step.sequenceIndex - 1 }),
           previous.feedStatus == .peaked
        {
            previous.feedStatus = .completed
        }

        plan.currentStepIndex = step.sequenceIndex

        let now = Date()
        step.startedAt = now
        step.feedStatus = .inProgress

        let delta = RevivalRescheduler.startDelta(
            scheduledTime: step.scheduledTime,
            startedAt: now
        )
        if delta != 0 {
            applyRevivalDelta(
                delta,
                fromIndex: step.sequenceIndex + 1,
                plan: plan,
                availability: availability,
                windows: windows
            )
        }
        syncRevivalActivity(plan: plan)
    }

    /// Records peak timing and moves the step to `.peaked`. Does not evaluate
    /// bake-readiness — that happens when the user answers the doubling question.
    func markRevivalStepPeak(
        step: RevivalFeedStep,
        plan: RevivalPlan,
        availability: UserAvailability?,
        windows: [UnavailableWindow]
    ) {
        let now = Date()
        step.peakTimestamp = now
        let reference = step.startedAt ?? step.scheduledTime
        step.timeToPeakMinutes = now.timeIntervalSince(reference) / 60
        step.feedStatus = .peaked

        let delta = RevivalRescheduler.peakDelta(
            scheduledTime: step.scheduledTime,
            startedAt: step.startedAt,
            peakAt: now,
            expectedPeakMinutes: step.expectedPeakMinutes,
            minPeakMinutes: step.minPeakMinutes,
            maxPeakMinutes: step.maxPeakMinutes
        )
        if delta != 0 {
            applyRevivalDelta(
                delta,
                fromIndex: step.sequenceIndex + 1,
                plan: plan,
                availability: availability,
                windows: windows
            )
        }

        syncRevivalActivity(plan: plan)
        scheduleNextRevivalReminder(plan: plan)
    }

    /// Evaluates bake-readiness on the final step after the user reports whether
    /// the starter doubled. Completes the plan or adds an extension feed.
    func evaluateBakeReadiness(
        step: RevivalFeedStep,
        plan: RevivalPlan,
        doubled: Bool,
        availability: UserAvailability?,
        windows: [UnavailableWindow],
        profile: StarterProfile? = nil
    ) -> Bool {
        let peakMinutes = step.timeToPeakMinutes ?? step.expectedPeakMinutes
        let maxPeak = step.maxPeakMinutes ?? step.expectedPeakMinutes * 1.5
        let peakedInWindow = peakMinutes <= maxPeak

        if doubled, peakedInWindow {
            step.feedStatus = .completed
            plan.revivalStatus = .completed
            if let profile,
               let result = StarterStateMachine.completeRevival(currentState: profile.starterLifecycleState)
            {
                profile.starterLifecycleState = result.newState
            }
            syncRevivalActivity(plan: plan)
            return true
        } else {
            addExtensionFeed(after: step, plan: plan, availability: availability, windows: windows)
            syncRevivalActivity(plan: plan)
            return false
        }
    }

    /// Adds an extension feed after the given step.
    private func addExtensionFeed(
        after step: RevivalFeedStep,
        plan: RevivalPlan,
        availability: UserAvailability?,
        windows: [UnavailableWindow]
    ) {
        let now = Date()
        let actualPeakMinutes = step.timeToPeakMinutes ?? step.expectedPeakMinutes
        let extensionPeak = max(actualPeakMinutes * 0.85, 180)

        let avail = availability.map { AvailabilityInput(from: $0) }
            ?? AvailabilityInput(startHour: 6, startMinute: 30, endHour: 21, endMinute: 0)
        let windowInputs = windows.map { WindowInput(from: $0) }
        let candidate = now.addingTimeInterval(30 * 60)
        let feedTime = FeedScheduler.snapToAvailableTime(
            candidate: candidate,
            availability: avail,
            windows: windowInputs
        ) ?? candidate

        let newIndex = step.sequenceIndex + 1
        let newStep = RevivalFeedStep(
            sequenceIndex: newIndex,
            scheduledTime: feedTime,
            expectedPeakMinutes: extensionPeak
        )
        newStep.plan = plan
        newStep.retainStarterGrams = step.retainStarterGrams
        newStep.addFlourGrams = step.addFlourGrams
        newStep.addWaterGrams = step.addWaterGrams
        newStep.minPeakMinutes = extensionPeak * 0.75
        newStep.maxPeakMinutes = extensionPeak * 1.5
        newStep.originalScheduledTime = feedTime

        let instruction = FeedInstructions.instruction(for: FeedInstructionInput(
            retainGrams: step.retainStarterGrams ?? 0,
            addFlourGrams: step.addFlourGrams ?? 0,
            addWaterGrams: step.addWaterGrams ?? 0,
            flourType: plan.flourType ?? "white",
            kitchenTempC: plan.kitchenTemperatureCelsius ?? 22,
            expectedPeakMinutes: extensionPeak,
            kind: .revivalFinal,
            hadHooch: false,
            neglect: plan.assessedNeglect.flatMap(StarterNeglectLevel.init(rawValue:))
        ))
        newStep.instructionTitle = "Feed \(newIndex + 1)"
        newStep.instructionBody = instruction.steps.joined(separator: "\n")
        newStep.instructionWatchFor = instruction.watchFor
        newStep.instructionExpectedWait = instruction.expectedWait
        newStep.instructionPeakGuidance = instruction.peakGuidance

        plan.estimatedBakeReadyDate = feedTime.addingTimeInterval(extensionPeak * 60)
        syncRevivalActivity(plan: plan)
        scheduleNextRevivalReminder(plan: plan)
    }

    // MARK: - Private

    private func applyRevivalDelta(
        _ delta: TimeInterval,
        fromIndex startIndex: Int,
        plan: RevivalPlan,
        availability: UserAvailability?,
        windows: [UnavailableWindow]
    ) {
        let avail = availability.map { AvailabilityInput(from: $0) }
            ?? AvailabilityInput(startHour: 6, startMinute: 30, endHour: 21, endMinute: 0)
        let windowInputs = windows.map { WindowInput(from: $0) }

        let sortedSteps = plan.feedSteps.sorted { $0.sequenceIndex < $1.sequenceIndex }
        let planID = plan.persistentModelID.hashValue.description
        for step in sortedSteps where step.sequenceIndex >= startIndex && step.feedStatus == .pending {
            let shifted = step.scheduledTime.addingTimeInterval(delta)
            let snapped = FeedScheduler.snapToAvailableTime(
                candidate: shifted,
                availability: avail,
                windows: windowInputs
            ) ?? shifted
            step.scheduledTime = snapped

            let stepIndex = step.sequenceIndex
            let title = step.instructionTitle ?? "Feed \(stepIndex + 1)"
            let newTime = snapped
            Task {
                await NotificationService.shared.rescheduleRevivalMixReminderIfPending(
                    at: newTime,
                    planID: planID,
                    stepIndex: stepIndex,
                    title: title
                )
            }
        }

        if let lastPending = sortedSteps.last(where: { $0.feedStatus == .pending }) {
            plan.estimatedBakeReadyDate = lastPending.scheduledTime
                .addingTimeInterval(lastPending.expectedPeakMinutes * 60)
        }
    }

    private func applyFallbackInstructions(plan: RevivalPlan, totalSteps: Int) {
        let kitchenTemp = plan.kitchenTemperatureCelsius ?? 22
        let flour = plan.flourType ?? "white"
        let neglect = plan.assessedNeglect.flatMap(StarterNeglectLevel.init(rawValue:))

        for step in plan.feedSteps {
            let kind = RevivalPlanGenerator.stepKind(index: step.sequenceIndex, totalSteps: totalSteps)
            let instruction = FeedInstructions.instruction(
                for: FeedInstructionInput(
                    retainGrams: step.retainStarterGrams ?? 0,
                    addFlourGrams: step.addFlourGrams ?? 0,
                    addWaterGrams: step.addWaterGrams ?? 0,
                    flourType: flour,
                    kitchenTempC: kitchenTemp,
                    expectedPeakMinutes: step.expectedPeakMinutes,
                    kind: kind,
                    hadHooch: plan.hadHooch && step.sequenceIndex == 0,
                    neglect: neglect
                )
            )
            step.instructionTitle = instruction.title
            step.instructionBody = instruction.steps.joined(separator: "\n")
            step.instructionWatchFor = instruction.watchFor
            step.instructionExpectedWait = instruction.expectedWait
            step.instructionPeakGuidance = instruction.peakGuidance
        }
    }

    private func resetRevivalForm() {
        revivalDaysSinceLastFed = nil
        revivalHasHooch = false
        revivalSmellsAcetone = false
        revivalHasBubbles = false
        revivalHasPinkOrangeOrMold = false
        revivalNotes = ""
        revivalStarterGrams = "20"
        showStartRevival = false
    }

    // MARK: - Revival Notifications

    private func scheduleNextRevivalReminder(plan: RevivalPlan) {
        let steps = plan.feedSteps.sorted { $0.sequenceIndex < $1.sequenceIndex }
        guard let next = steps.first(where: { $0.feedStatus == .pending }),
              next.scheduledTime > Date()
        else { return }

        let planID = plan.persistentModelID.hashValue.description
        let stepIndex = next.sequenceIndex
        let title = next.instructionTitle ?? "Feed \(stepIndex + 1)"
        let date = next.scheduledTime
        Task {
            await NotificationService.shared.scheduleRevivalMixReminder(
                at: date,
                planID: planID,
                stepIndex: stepIndex,
                title: title
            )
        }
    }

    // MARK: - Live Activity

    private func syncRevivalActivity(plan: RevivalPlan) {
        guard plan.revivalStatus == .active else {
            LiveActivityService.shared.endRevivalActivity()
            return
        }

        let state = LiveActivityService.buildRevivalState(from: plan)
        if LiveActivityService.shared.hasRevivalActivity {
            LiveActivityService.shared.updateRevivalActivity(state: state)
        } else {
            LiveActivityService.shared.startRevivalActivity(
                planStartDate: plan.startDate,
                state: state
            )
        }
    }
}
