import Foundation
import Observation
import SwiftData

@Observable
@MainActor
final class StarterViewModel {
    var showLogFeed = false
    var showStartRevival = false

    // Feed entry form state
    var feedRatioStarter = 1
    var feedRatioFlour = 5
    var feedRatioWater = 5
    var feedFlourType = "white"
    var feedKitchenTemp = 22.0
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

    func logFeed(modelContext: ModelContext) {
        let grams = Double(logFeedStarterGrams.trimmingCharacters(in: .whitespaces))
        let log = StarterFeedLog(
            ratioStarter: feedRatioStarter,
            ratioFlour: feedRatioFlour,
            ratioWater: feedRatioWater,
            flourType: feedFlourType,
            kitchenTemperatureCelsius: feedKitchenTemp,
            starterGrams: grams
        )
        modelContext.insert(log)

        // Reset form
        feedRatioStarter = 1
        feedRatioFlour = 5
        feedRatioWater = 5
        feedFlourType = "white"
        logFeedStarterGrams = ""

        showLogFeed = false
    }

    func markPeak(for log: StarterFeedLog, profile: StarterProfile?, allLogs: [StarterFeedLog]) {
        log.markPeak(at: Date())
        updateProfileAverages(profile: profile, feedLogs: allLogs)
    }

    /// Recalculates the starter profile's average time-to-peak from feed history.
    func updateProfileAverages(profile: StarterProfile?, feedLogs: [StarterFeedLog]) {
        guard let profile else { return }

        let peakTimes = feedLogs.compactMap(\.timeToPeakMinutes)
        guard !peakTimes.isEmpty else { return }

        profile.averageTimeToPeakMinutes = peakTimes.reduce(0, +) / Double(peakTimes.count)
        profile.starterHealthStatus = healthStatus(profile: profile, feedLogs: feedLogs)
        profile.lastUpdated = Date()
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
        plan.estimatedBakeReadyDate = RevivalPlanGenerator.estimatedBakeReadyDate(
            startTime: startTime,
            neglect: neglect,
            kitchenTempC: revivalKitchenTemp
        )
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

        // Populate offline-fallback copy first, so we always have something to show.
        applyFallbackInstructions(plan: plan, totalSteps: totalSteps)

        // Then ask the LLM coach to personalise — overwrites fallback where successful.
        revivalIsPreparing = true
        defer { revivalIsPreparing = false }

        let plannedSteps = feedPlans.map { feedPlan in
            PlannedStep(
                sequenceIndex: feedPlan.sequenceIndex,
                retainGrams: feedPlan.retainStarterGrams,
                addFlourGrams: feedPlan.addFlourGrams,
                addWaterGrams: feedPlan.addWaterGrams,
                expectedPeakMinutes: feedPlan.expectedPeakMinutes,
                kind: RevivalPlanGenerator.stepKind(index: feedPlan.sequenceIndex, totalSteps: totalSteps)
            )
        }

        let coaching = await LLMService().composeRevivalCoaching(
            RevivalCoachingRequest(
                neglect: neglect,
                hadHooch: revivalHasHooch,
                daysSinceLastFed: revivalDaysSinceLastFed,
                initialStarterGrams: grams,
                flourType: revivalFlourType,
                kitchenTempC: revivalKitchenTemp,
                userNotes: plan.userNotes,
                steps: plannedSteps
            )
        )

        if let coaching {
            plan.coachOpeningRead = coaching.openingRead
            for coached in coaching.steps {
                guard let step = stepsByIndex[coached.sequenceIndex] else { continue }
                step.instructionTitle = coached.title
                step.instructionBody = coached.bullets.joined(separator: "\n")
                step.instructionWatchFor = coached.watchFor
                step.instructionExpectedWait = coached.expectedWait
            }
        }

        // Reset wizard form.
        resetRevivalForm()
        return plan
    }

    /// Marks the current revival step as mixed & covered. Cascades a delta to later
    /// steps when the user is more than a grace window late.
    func markRevivalStepStarted(
        step: RevivalFeedStep,
        plan: RevivalPlan,
        availability: UserAvailability?,
        windows: [UnavailableWindow]
    ) {
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
    }

    /// Records peak, advances to the next step, and cascades a delta if the peak
    /// landed outside the step's tolerance band.
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
        step.feedStatus = .completed

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

        let sortedSteps = plan.feedSteps.sorted { $0.sequenceIndex < $1.sequenceIndex }
        if step.sequenceIndex >= sortedSteps.count - 1 {
            plan.revivalStatus = .completed
        } else {
            plan.currentStepIndex = step.sequenceIndex + 1
        }
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
        for step in sortedSteps where step.sequenceIndex >= startIndex && step.feedStatus == .pending {
            let shifted = step.scheduledTime.addingTimeInterval(delta)
            let snapped = FeedScheduler.snapToAvailableTime(
                candidate: shifted,
                availability: avail,
                windows: windowInputs
            ) ?? shifted
            step.scheduledTime = snapped
        }

        if let bakeReady = plan.estimatedBakeReadyDate {
            plan.estimatedBakeReadyDate = bakeReady.addingTimeInterval(delta)
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
}
