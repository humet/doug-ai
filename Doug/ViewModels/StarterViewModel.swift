import Foundation
import Observation
import SwiftData

/// The one thing the starter hero card asks the user to do next, derived from
/// lifecycle state and bake context.
enum StarterPrimaryAction: Equatable {
    case activateAndFeed
    case logActivationFeed
    case markPeak
    case buildLevain
    case feedAndRefrigerate
    case waitForBake
    case followRevival
}

@Observable
@MainActor
final class StarterViewModel {
    var showLogFeed = false
    var showStartRevival = false
    var showPostBake = false
    var editingFeedLog: StarterFeedLog?
    /// Feed log the Mark Peak sheet is targeting.
    var markPeakTarget: StarterFeedLog?
    /// When set, the Log Feed sheet locks to this intent (e.g. the merged
    /// "Activate & Feed" flow) instead of offering the feed-type picker.
    var logFeedLockedIntent: FeedIntent?

    // Feed entry form state
    var feedRatioStarter = 1
    var feedRatioFlour = 1
    var feedRatioWater = 1
    var feedFlourType = "white"
    var feedKitchenTemp = 22.0
    var feedTimestamp = Date()
    var logFeedStarterGrams = ""
    /// User-selectable feed type in the Log Feed sheet. Drives the suggested
    /// ratios and guidance independently of lifecycle state, so a starter can be
    /// fed for the counter or the fridge from any state.
    var feedIntent: FeedIntent = .maintenance

    // Levain build state
    var pendingLevainBuild: LevainBuildCalculator.Result?
    var pendingLevainRecipeName: String?

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

    func prepareLevainBuild(for recipe: Recipe, kitchenTemp: Double, levainGramsNeeded: Double? = nil) {
        let result = LevainBuildCalculator.calculate(.init(
            levainGramsNeeded: levainGramsNeeded ?? recipe.ingredients.levainGrams,
            baseRatio: recipe.levainBuildRatio,
            referenceTemp: recipe.referenceTemperatureCelsius,
            kitchenTemp: kitchenTemp
        ))
        pendingLevainBuild = result
        pendingLevainRecipeName = recipe.name

        feedRatioStarter = result.ratio.starter
        feedRatioFlour = result.ratio.flour
        feedRatioWater = result.ratio.water
        logFeedStarterGrams = "\(Int(result.starterGrams))"
        feedKitchenTemp = kitchenTemp
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

        // Keep storage + lifecycle honest with the feed the user just logged, so
        // the hero card can't claim "Counter / Active" right after a fridge feed
        // (or vice versa):
        //  • a counter/activation feed while dormant → take it out onto the counter
        //    so the activation flow (Mark Peak → ready) becomes reachable
        //  • a fridge/maintenance feed while it's out → put it back in the fridge
        if let profile {
            let state = profile.starterLifecycleState
            if resolvedIntent == .activation, state == .dormant {
                activate(profile: profile)
            } else if resolvedIntent == .maintenance, state == .active || state == .activating {
                refrigerate(profile: profile)
            }
        }

        switch resolvedIntent {
        case .activation:
            post(.activationFeedLogged(at: log.timestamp))
        case .levain:
            post(.levainFeedLogged(at: log.timestamp))
        case .maintenance, .postBake:
            break
        }

        feedRatioStarter = 1
        feedRatioFlour = 2
        feedRatioWater = 2
        feedFlourType = "white"
        feedTimestamp = Date()
        logFeedStarterGrams = ""
        feedIntent = .maintenance
        logFeedLockedIntent = nil
        pendingLevainBuild = nil
        pendingLevainRecipeName = nil

        showLogFeed = false

        // A feed is precious user data — persist now rather than waiting for
        // autosave, which an abrupt termination can beat.
        try? modelContext.save()
    }

    private func inferFeedIntent(profile: StarterProfile?) -> FeedIntent {
        if pendingLevainBuild != nil { return .levain }
        return switch profile?.starterLifecycleState {
        case .activating: .activation
        case .active: .maintenance
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
        try? modelContext.save()
    }

    /// Cross-ViewModel channel: the Schedule tab observes these to keep a live
    /// schedule's activation preamble in step with Starter-tab actions. The
    /// notification's `object` is the `StarterTabEvent`.
    static let starterEventNotification = Notification.Name("StarterTabEvent")

    private func post(_ event: StarterTabEvent) {
        NotificationCenter.default.post(name: Self.starterEventNotification, object: event)
    }

    /// Marks a feed's peak at an explicit (possibly backdated) time. With
    /// `estimated: true` the peak timestamp is recorded but the duration is
    /// deliberately dropped, so a guess never feeds the scheduler's averages.
    func markPeak(
        for log: StarterFeedLog,
        at peakDate: Date = Date(),
        estimated: Bool = false,
        profile: StarterProfile?,
        allLogs: [StarterFeedLog]
    ) {
        if estimated {
            log.markEstimatedPeak(at: peakDate)
        } else {
            log.markPeak(at: peakDate)
        }
        updateProfileAverages(profile: profile, feedLogs: allLogs)

        // The user explicitly confirmed the peak, so always advance
        // activating → active. The auto-transition path can't be used here: it
        // requires a plausible timeToPeakMinutes and would strand estimated or
        // badly-backdated peaks in `.activating`.
        if log.starterFeedIntent == .activation, let profile,
           let result = StarterStateMachine.markPeakConfirmed(currentState: profile.starterLifecycleState)
        {
            profile.starterLifecycleState = result.newState
            profile.starterStorageType = .counter
        }

        post(.peakMarked(at: peakDate, intent: log.starterFeedIntent))

        try? log.modelContext?.save()
    }

    /// Best estimate of when an unobserved feed peaked, for the "it peaked
    /// while I slept" flow.
    func estimatedPeakDate(for log: StarterFeedLog, profile: StarterProfile?) -> Date {
        StarterPeakEstimator.estimatedPeakDate(
            feedTimestamp: log.timestamp,
            activePeakAverageMinutes: profile?.activePeakAverageMinutes,
            averageTimeToPeakMinutes: profile?.averageTimeToPeakMinutes,
            kitchenTempCelsius: log.kitchenTemperatureCelsius
        )
    }

    /// When a currently-rising feed is expected to peak, for the hero card's
    /// "expect peak ~13:40" line.
    func expectedPeakDate(
        for log: StarterFeedLog,
        profile: StarterProfile?,
        allLogs: [StarterFeedLog]
    ) -> Date {
        let minutes: Double = if log.starterFeedIntent == .activation {
            StarterScheduleSync.expectedPeakMinutes(
                peakProfile: StarterPeakProfile(
                    feedLogs: allLogs.map { FeedLogInput(from: $0) },
                    intentFilter: .activation
                ),
                activePeakAverageMinutes: profile?.activePeakAverageMinutes,
                kitchenTempCelsius: log.kitchenTemperatureCelsius
            )
        } else {
            TemperatureCalculator.levainBuildMinutes(kitchenTemp: log.kitchenTemperatureCelsius)
        }
        return log.timestamp.addingTimeInterval(minutes * 60)
    }

    /// The single next action the hero card should offer.
    func primaryAction(
        lifecycleState: StarterLifecycleState,
        hasRisingFeed: Bool,
        hasUpcomingRecipe: Bool,
        hasRecentLevainFeed: Bool,
        bakeAwaitingLevainMix: Bool
    ) -> StarterPrimaryAction {
        switch lifecycleState {
        case .reviving:
            return .followRevival
        case .dormant:
            // Always offer activation — even when health says "needs revival"
            // (which is also a fresh install's state, with zero feed history).
            // The revival section below carries its own call to action.
            return .activateAndFeed
        case .activating:
            return hasRisingFeed ? .markPeak : .logActivationFeed
        case .active:
            if bakeAwaitingLevainMix { return .waitForBake }
            if hasUpcomingRecipe, !hasRecentLevainFeed { return .buildLevain }
            return .feedAndRefrigerate
        }
    }

    func updateProfileAverages(profile: StarterProfile?, feedLogs: [StarterFeedLog]) {
        guard let profile else { return }

        // Exclude implausible readings (e.g. a peak marked days late) so one bad
        // entry can't corrupt the averages the scheduler relies on — shared with
        // the schedule's step side effects via StarterAverages.
        let averages = StarterAverages.recompute(feedLogs: feedLogs.map { FeedLogInput(from: $0) })
        if let allAverage = averages.averageTimeToPeakMinutes {
            profile.averageTimeToPeakMinutes = allAverage
        }
        if let activationAverage = averages.activePeakAverageMinutes {
            profile.activePeakAverageMinutes = activationAverage
        }

        profile.starterHealthStatus = healthStatus(profile: profile, feedLogs: feedLogs)
        profile.lastUpdated = Date()
    }

    // MARK: - Lifecycle

    func activate(profile: StarterProfile) {
        if let result = StarterStateMachine.activate(currentState: profile.starterLifecycleState) {
            profile.starterLifecycleState = result.newState
            profile.starterStorageType = .counter
            post(.activated(at: Date()))
        }
    }

    func refrigerate(profile: StarterProfile) {
        if let result = StarterStateMachine.refrigerate(currentState: profile.starterLifecycleState) {
            profile.starterLifecycleState = result.newState
            profile.starterStorageType = .fridge
        }
    }

    func feedAndRefrigerate(profile: StarterProfile, modelContext: ModelContext) {
        logFeed(modelContext: modelContext, profile: profile, intent: .maintenance)
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
            if result.newState == .activating || result.newState == .active {
                profile.starterStorageType = .counter
            }
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
            storageType: profile.starterStorageType,
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
                if result.newState == .activating || result.newState == .active {
                    profile.starterStorageType = .counter
                }
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
