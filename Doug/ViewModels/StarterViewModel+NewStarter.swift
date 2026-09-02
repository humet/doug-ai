import Foundation
import SwiftData

/// Starting a starter that doesn't exist yet — from scratch, from a dried
/// culture, from a friend's jar, or from a shop kit.
///
/// Deliberately built on the revival plan machinery: a new-starter plan is the
/// same shape (dated feeds, per-step copy, grams, notifications, Live Activity),
/// so it reuses `RevivalPlan`, `RevivalFeedStep`, and the rescheduling in
/// `applyRevivalDelta`. What differs is how it progresses — by what the user
/// reports seeing rather than by peak timing alone.
extension StarterViewModel {
    /// Everything the start sheet collects.
    struct NewStarterRequest {
        let origin: StarterOrigin
        let seedGrams: Double
        let flourType: String
        let kitchenTempC: Double
        /// Nil starts now; set when the user delays to keep a peak out of the night.
        let startAt: Date?

        init(
            origin: StarterOrigin,
            seedGrams: Double,
            flourType: String,
            kitchenTempC: Double,
            startAt: Date? = nil
        ) {
            self.origin = origin
            self.seedGrams = seedGrams
            self.flourType = flourType
            self.kitchenTempC = kitchenTempC
            self.startAt = startAt
        }
    }

    // MARK: - Starting

    /// Creates a new-starter plan and puts the profile into `.establishing`.
    @discardableResult
    func startNewStarter(
        _ request: NewStarterRequest,
        availability: UserAvailability?,
        windows: [UnavailableWindow],
        profile: StarterProfile?,
        modelContext: ModelContext
    ) -> RevivalPlan {
        let startTime = request.startAt ?? Date()
        let environment = planEnvironment(
            kitchenTempC: request.kitchenTempC,
            availability: availability,
            windows: windows
        )

        let steps = StarterOriginPlanner.plan(StarterOriginPlanInput(
            origin: request.origin,
            startTime: startTime,
            seedGrams: request.seedGrams,
            environment: environment,
            flourType: request.flourType
        ))

        let plan = RevivalPlan()
        plan.startDate = startTime
        plan.starterOrigin = request.origin
        plan.establishPhase = steps.first?.phase ?? .initialMix
        plan.targetStepCount = steps.count
        plan.estimatedBakeReadyDate = StarterOriginPlanner.estimatedReadyDate(from: steps)
        plan.initialStarterGrams = request.seedGrams
        plan.flourType = request.flourType
        plan.kitchenTemperatureCelsius = request.kitchenTempC
        modelContext.insert(plan)

        for programStep in steps {
            let step = makeStep(from: programStep)
            step.plan = plan
            applyInstruction(to: step, plan: plan)
        }

        if let profile,
           let result = StarterStateMachine.startEstablishing(currentState: profile.starterLifecycleState)
        {
            profile.starterLifecycleState = result.newState
            // A new starter lives on the counter until it's established.
            profile.starterStorageType = .counter
        }

        showStartNewStarter = false
        syncRevivalActivity(plan: plan)
        scheduleNextRevivalReminder(plan: plan)
        return plan
    }

    /// Records that the user's starter has died, so the app stops asking them
    /// to feed something that's in the bin.
    func markStarterDead(profile: StarterProfile?) {
        guard let profile else { return }
        profile.hasStarter = false
        profile.starterLifecycleState = .dormant
        profile.starterHealthStatus = .needsRevival
        profile.averageTimeToPeakMinutes = nil
        profile.activePeakAverageMinutes = nil
        profile.lastUpdated = Date()
    }

    // MARK: - Progressing

    /// Records a check-in on the current step and reshapes the plan around it.
    ///
    /// Pass `signals: nil` for the opening mix or rehydration, where there is
    /// nothing in the jar to observe yet.
    @discardableResult
    func recordEstablishCheckIn(
        step: RevivalFeedStep,
        plan: RevivalPlan,
        signals: StarterCheckInSignals?,
        availability: UserAvailability?,
        windows: [UnavailableWindow],
        profile: StarterProfile?
    ) -> EstablishOutcome {
        guard let origin = plan.starterOrigin else { return .holdCourse }

        let phase = step.establishPhase ?? plan.establishPhase ?? .initialMix
        let observed = signals ?? StarterCheckInSignals(
            hasBubbles: false, hasRisen: false, hasDoubled: false, smell: .nothing
        )

        if signals != nil {
            step.recordedSignals = observed
        }

        // A confirming feed only counts as a run of doubles if it keeps doubling.
        if phase == .confirming {
            plan.consecutiveDoubles = observed.hasDoubled ? plan.consecutiveDoubles + 1 : 0
        }

        let outcome = StarterEstablishProgress.evaluate(
            origin: origin,
            phase: phase,
            dayNumber: step.dayNumber ?? 1,
            signals: observed,
            consecutiveDoubles: max(plan.consecutiveDoubles - 1, 0)
        )

        completeStep(step, in: plan, availability: availability, windows: windows)
        // nil for .holdCourse, which clears any stale notice.
        plan.establishNotice = outcome.notice

        switch outcome {
        case .complete:
            completeEstablishment(plan: plan, finalStep: step, profile: profile)
        case let .advancePhase(next):
            advance(plan: plan, to: next, after: step, availability: availability, windows: windows)
        case let .stalled(_, extraFeeds):
            appendSteps(
                count: extraFeeds,
                kind: step.starterStepKind,
                phase: phase,
                to: plan,
                availability: availability,
                windows: windows
            )
        case let .needsMoreConfirming(extraFeeds):
            appendSteps(
                count: extraFeeds,
                kind: .readinessTest,
                phase: .confirming,
                to: plan,
                availability: availability,
                windows: windows
            )
        case .falseRise, .holdCourse:
            // Nothing to reshape. A false rise is informational only — the
            // plan carries on exactly as generated, which is the whole point.
            break
        }

        syncRevivalActivity(plan: plan)
        scheduleNextRevivalReminder(plan: plan)
        return outcome
    }

    /// The starter is established. Bump the generation so the retired starter's
    /// readings stop influencing scheduling, and seed the new one with the
    /// time-to-peak it just proved.
    func completeEstablishment(
        plan: RevivalPlan,
        finalStep: RevivalFeedStep?,
        profile: StarterProfile?
    ) {
        plan.revivalStatus = .completed

        guard let profile else { return }

        if let result = StarterStateMachine.completeEstablishing(currentState: profile.starterLifecycleState) {
            profile.starterLifecycleState = result.newState
        }
        profile.hasStarter = true
        profile.starterGeneration += 1
        profile.starterBornAt = Date()
        profile.starterStorageType = .counter
        // Averages belong to the starter that produced them.
        profile.averageTimeToPeakMinutes = nil
        profile.activePeakAverageMinutes = nil
        profile.starterHealthStatus = .readyToBake
        profile.lastUpdated = Date()

        if let finalStep {
            seedFirstFeedLog(from: finalStep, plan: plan, profile: profile)
        }
    }

    func cancelNewStarter(plan: RevivalPlan, profile: StarterProfile?) {
        plan.revivalStatus = .cancelled
        NotificationService.shared.cancelAllRevivalReminders(
            planID: notificationPlanID(for: plan),
            stepCount: plan.feedSteps.count
        )
        if let profile,
           let result = StarterStateMachine.cancelEstablishing(currentState: profile.starterLifecycleState)
        {
            profile.starterLifecycleState = result.newState
        }
        LiveActivityService.shared.endRevivalActivity()
    }

    // MARK: - Generations

    /// Feed logs belonging to the starter the user actually has now.
    ///
    /// A dead starter's readings stay in history but must never reach the
    /// averages, health assessment, or levain-wait estimates — one junk peak
    /// time is enough to knock out every available bake slot.
    func currentGeneration(
        _ logs: [StarterFeedLog],
        profile: StarterProfile?
    ) -> [StarterFeedLog] {
        guard let profile else { return logs }
        return logs.filter { $0.starterGeneration >= profile.starterGeneration }
    }

    // MARK: - Plan Shaping

    private func completeStep(
        _ step: RevivalFeedStep,
        in plan: RevivalPlan,
        availability: UserAvailability?,
        windows: [UnavailableWindow]
    ) {
        let now = Date()
        if step.startedAt == nil {
            step.startedAt = now
        }
        step.feedStatus = .completed

        // Shift what's left if the user fed early or late.
        let delta = RevivalRescheduler.startDelta(scheduledTime: step.scheduledTime, startedAt: now)
        if delta != 0 {
            applyRevivalDelta(
                delta,
                fromIndex: step.sequenceIndex + 1,
                plan: plan,
                availability: availability,
                windows: windows
            )
        }

        if let next = sortedSteps(of: plan).first(where: { $0.feedStatus == .pending }) {
            plan.currentStepIndex = next.sequenceIndex
            // The plan's phase is whatever the current step belongs to. An
            // explicit `.advancePhase` outcome may override this below.
            if let nextPhase = next.establishPhase {
                plan.establishPhase = nextPhase
            }
        }
    }

    /// Skips the remainder of an outrun phase and pulls the next step forward.
    private func advance(
        plan: RevivalPlan,
        to next: StarterEstablishPhase,
        after step: RevivalFeedStep,
        availability: UserAvailability?,
        windows: [UnavailableWindow]
    ) {
        plan.establishPhase = next

        // Drop pending steps from phases the starter has already outrun.
        for pending in sortedSteps(of: plan)
            where pending.feedStatus == .pending
            && (pending.establishPhase?.sortOrder ?? next.sortOrder) < next.sortOrder
        {
            NotificationService.shared.cancelRevivalMixReminder(
                planID: notificationPlanID(for: plan),
                stepIndex: pending.sequenceIndex
            )
            pending.plan = nil
            plan.feedSteps.removeAll { $0 === pending }
        }

        guard let upcoming = sortedSteps(of: plan).first(where: { $0.feedStatus == .pending }) else {
            plan.estimatedBakeReadyDate = Date()
            return
        }

        plan.currentStepIndex = upcoming.sequenceIndex

        // The next feed is due one interval after the one just done, not at
        // the date the skipped steps used to occupy.
        let cadence = StepShape.forKind(upcoming.starterStepKind).cadence
        let desired = (step.startedAt ?? Date()).addingTimeInterval(cadence * 60)
        let delta = desired.timeIntervalSince(upcoming.scheduledTime)
        if abs(delta) > 60 {
            applyRevivalDelta(
                delta,
                fromIndex: upcoming.sequenceIndex,
                plan: plan,
                availability: availability,
                windows: windows
            )
        }
    }

    private func appendSteps(
        count: Int,
        kind: StarterStepKind,
        phase: StarterEstablishPhase,
        to plan: RevivalPlan,
        availability: UserAvailability?,
        windows: [UnavailableWindow]
    ) {
        let existing = sortedSteps(of: plan)
        guard let last = existing.last else { return }

        let environment = planEnvironment(
            kitchenTempC: plan.kitchenTemperatureCelsius ?? StarterOriginPlanner.referenceKitchenTempC,
            availability: availability,
            windows: windows
        )

        // Anchor to the final step so new indices can't collide with existing ones.
        let template = programStep(from: last)
        let cadence = StepShape.forKind(kind).cadence
        let startingAt = max(Date(), last.scheduledTime).addingTimeInterval(cadence * 60)

        let extras = StarterOriginPlanner.extensionSteps(
            StarterPlanExtension(
                template: template,
                count: count,
                startingAt: startingAt,
                planStartDate: plan.startDate,
                kind: kind,
                phase: phase
            ),
            environment: environment
        )

        for programStep in extras {
            let step = makeStep(from: programStep)
            step.plan = plan
            applyInstruction(to: step, plan: plan)
        }

        if let newLast = extras.last {
            plan.estimatedBakeReadyDate = newLast.scheduledTime
                .addingTimeInterval(newLast.expectedPeakMinutes * 60)
        }
    }

    // MARK: - Conversions

    private func makeStep(from programStep: StarterProgramStep) -> RevivalFeedStep {
        let step = RevivalFeedStep(
            sequenceIndex: programStep.sequenceIndex,
            scheduledTime: programStep.scheduledTime,
            expectedPeakMinutes: programStep.expectedPeakMinutes,
            targetRatioStarter: programStep.ratioStarter,
            targetRatioFlour: programStep.ratioFlour,
            targetRatioWater: programStep.ratioWater
        )
        step.starterStepKind = programStep.kind
        step.establishPhase = programStep.phase
        step.dayNumber = programStep.dayNumber
        step.originalScheduledTime = programStep.scheduledTime
        step.retainStarterGrams = programStep.retainStarterGrams
        step.addFlourGrams = programStep.addFlourGrams
        step.addWaterGrams = programStep.addWaterGrams
        step.minPeakMinutes = programStep.minPeakMinutes
        step.maxPeakMinutes = programStep.maxPeakMinutes
        return step
    }

    private func programStep(from step: RevivalFeedStep) -> StarterProgramStep {
        StarterProgramStep(
            sequenceIndex: step.sequenceIndex,
            dayNumber: step.dayNumber ?? 1,
            kind: step.starterStepKind,
            phase: step.establishPhase ?? .confirming,
            scheduledTime: step.scheduledTime,
            expectsPeak: step.expectsPeak,
            expectedPeakMinutes: step.expectedPeakMinutes,
            minPeakMinutes: step.minPeakMinutes,
            maxPeakMinutes: step.maxPeakMinutes,
            retainStarterGrams: step.retainStarterGrams ?? 0,
            addFlourGrams: step.addFlourGrams ?? 0,
            addWaterGrams: step.addWaterGrams ?? 0,
            ratioStarter: step.targetRatioStarter,
            ratioFlour: step.targetRatioFlour,
            ratioWater: step.targetRatioWater
        )
    }

    private func planEnvironment(
        kitchenTempC: Double,
        availability: UserAvailability?,
        windows: [UnavailableWindow]
    ) -> StarterPlanEnvironment {
        StarterPlanEnvironment(
            kitchenTempC: kitchenTempC,
            availability: availability.map { AvailabilityInput(from: $0) }
                ?? AvailabilityInput(startHour: 6, startMinute: 30, endHour: 21, endMinute: 0),
            windows: windows.map { WindowInput(from: $0) }
        )
    }

    private func applyInstruction(to step: RevivalFeedStep, plan: RevivalPlan) {
        let instruction = FeedInstructions.instruction(for: FeedInstructionInput(
            retainGrams: step.retainStarterGrams ?? 0,
            addFlourGrams: step.addFlourGrams ?? 0,
            addWaterGrams: step.addWaterGrams ?? 0,
            flourType: plan.flourType ?? "whole wheat",
            kitchenTempC: plan.kitchenTemperatureCelsius ?? StarterOriginPlanner.referenceKitchenTempC,
            expectedPeakMinutes: step.expectedPeakMinutes,
            kind: step.starterStepKind.feedStepKind,
            hadHooch: false,
            neglect: nil,
            origin: plan.starterOrigin,
            dayNumber: step.dayNumber
        ))
        step.instructionTitle = instruction.title
        step.instructionBody = instruction.steps.joined(separator: "\n")
        step.instructionWatchFor = instruction.watchFor
        step.instructionExpectedWait = instruction.expectedWait
        step.instructionPeakGuidance = instruction.peakGuidance
    }

    /// Gives the finished starter one real time-to-peak reading to schedule
    /// with, rather than leaving the scheduler on temperature estimates alone.
    private func seedFirstFeedLog(
        from step: RevivalFeedStep,
        plan: RevivalPlan,
        profile: StarterProfile
    ) {
        guard let context = plan.modelContext else { return }

        let log = StarterFeedLog(
            timestamp: step.startedAt ?? step.scheduledTime,
            ratioStarter: step.targetRatioStarter,
            ratioFlour: step.targetRatioFlour,
            ratioWater: step.targetRatioWater,
            flourType: plan.flourType ?? "whole wheat",
            kitchenTemperatureCelsius: plan.kitchenTemperatureCelsius
                ?? StarterOriginPlanner.referenceKitchenTempC,
            starterGrams: step.retainStarterGrams,
            feedIntent: .activation,
            starterGeneration: profile.starterGeneration
        )
        context.insert(log)

        // markPeak applies the plausibility filter, so a peak marked days late
        // can't seed the new starter with a junk reading.
        if let peak = step.peakTimestamp {
            log.markPeak(at: peak)
        }
    }

    private func sortedSteps(of plan: RevivalPlan) -> [RevivalFeedStep] {
        plan.feedSteps.sorted { $0.sequenceIndex < $1.sequenceIndex }
    }

    private func notificationPlanID(for plan: RevivalPlan) -> String {
        plan.persistentModelID.hashValue.description
    }
}
