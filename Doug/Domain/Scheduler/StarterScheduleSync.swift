import Foundation

// MARK: - Starter Tab Events

/// A starter mutation originating on the Starter tab that a live schedule's
/// activation preamble must reflect. Counterpart of `BakeCoordinator`, which
/// computes starter side effects for schedule events; this computes schedule
/// effects for starter events.
enum StarterTabEvent {
    /// The starter was taken out of the fridge (dormant → activating). The
    /// activation feed hasn't been logged yet.
    case activated(at: Date)
    /// An activation feed was logged.
    case activationFeedLogged(at: Date)
    /// A levain build feed was logged.
    case levainFeedLogged(at: Date)
    /// The user marked a feed's peak. `at` may be backdated or estimated.
    case peakMarked(at: Date, intent: FeedIntent)
}

// MARK: - Step Snapshots & Effects

/// Value snapshot of a top-level schedule step. Domain code can't see the
/// `ScheduleStep` @Model, so the ViewModel snapshots its step array and maps
/// returned effects back by `index`.
struct ScheduleStepSnapshot {
    let index: Int
    let stepTypeID: StepTypeID
    let status: StepStatus
    let startTime: Date
    let endTime: Date
}

enum ScheduleSyncEffect: Equatable {
    /// Complete the step as done at the given time (markStepDone semantics,
    /// with starter side effects suppressed — the starter already changed).
    case completeStep(index: Int, at: Date)
    /// Make the step active starting at the given time.
    case startStep(index: Int, at: Date)
    /// Move the step's end (and re-derive its duration), cascading downstream.
    case retimeStepEnd(index: Int, newEnd: Date)
}

// MARK: - Sync

enum StarterScheduleSync {
    /// Lead-in steps that fill time before activation but aren't themselves
    /// actions — they complete silently once the user acts out-of-band.
    private static let fillerStepTypes: Set<StepTypeID> = [.fridgeRest, .holdStarter]

    static func effects(
        for event: StarterTabEvent,
        steps: [ScheduleStepSnapshot],
        expectedPeakMinutes: Double,
        now: Date = Date()
    ) -> [ScheduleSyncEffect] {
        switch event {
        case let .activated(at):
            activatedEffects(at: at, steps: steps)
        case let .activationFeedLogged(at):
            activationFeedEffects(at: at, steps: steps, expectedPeakMinutes: expectedPeakMinutes, now: now)
        case let .levainFeedLogged(at):
            levainFeedEffects(at: at, steps: steps)
        case let .peakMarked(at, intent):
            peakMarkedEffects(at: at, intent: intent, steps: steps, now: now)
        }
    }

    private static func activatedEffects(
        at: Date,
        steps: [ScheduleStepSnapshot]
    ) -> [ScheduleSyncEffect] {
        var effects = completeOpenFillers(in: steps, at: at)
        if let activate = firstOpen(.activateStarter, in: steps) {
            effects.append(.startStep(index: activate.index, at: at))
        }
        return effects
    }

    private static func activationFeedEffects(
        at: Date,
        steps: [ScheduleStepSnapshot],
        expectedPeakMinutes: Double,
        now: Date
    ) -> [ScheduleSyncEffect] {
        var effects = completeOpenFillers(in: steps, at: at)
        if let activate = firstOpen(.activateStarter, in: steps) {
            effects.append(.completeStep(index: activate.index, at: at))
        }
        if let wait = firstOpen(.waitForPeak, in: steps) {
            let newEnd = max(at.addingTimeInterval(expectedPeakMinutes * 60), now)
            effects.append(.retimeStepEnd(index: wait.index, newEnd: newEnd))
        }
        return effects
    }

    /// The user built the levain out-of-band, so the whole preamble — and the
    /// Build Levain step itself — is satisfied. The caller's completion cascade
    /// re-glues the levain-peak wait to the feed time.
    private static func levainFeedEffects(
        at: Date,
        steps: [ScheduleStepSnapshot]
    ) -> [ScheduleSyncEffect] {
        guard let build = firstOpen(.buildLevain, in: steps) else { return [] }
        var effects = completeOpenFillers(in: steps, at: at)
        if let activate = firstOpen(.activateStarter, in: steps) {
            effects.append(.completeStep(index: activate.index, at: at))
        }
        if let wait = firstOpen(.waitForPeak, in: steps) {
            effects.append(.completeStep(index: wait.index, at: at))
        }
        effects.append(.completeStep(index: build.index, at: at))
        return effects
    }

    private static func peakMarkedEffects(
        at: Date,
        intent: FeedIntent,
        steps: [ScheduleStepSnapshot],
        now: Date
    ) -> [ScheduleSyncEffect] {
        switch intent {
        case .activation:
            guard let wait = firstOpen(.waitForPeak, in: steps) else { return [] }
            let predecessorTime = min(at, now)
            var effects = completeOpenFillers(in: steps, at: predecessorTime)
            if let activate = firstOpen(.activateStarter, in: steps) {
                effects.append(.completeStep(index: activate.index, at: predecessorTime))
            }
            effects.append(.completeStep(index: wait.index, at: at))
            return effects
        case .levain:
            guard let wait = firstOpen(.waitForLevainPeak, in: steps) else { return [] }
            return [.completeStep(index: wait.index, at: at)]
        default:
            return []
        }
    }

    /// Expected minutes from an activation feed to peak. Single home for the
    /// fallback chain: observed bucket average → profile's activation average →
    /// temperature-derived default.
    static func expectedPeakMinutes(
        peakProfile: StarterPeakProfile?,
        activePeakAverageMinutes: Double?,
        kitchenTempCelsius: Double
    ) -> Double {
        let bracket = TemperatureBracket.bracket(celsius: kitchenTempCelsius)
        if let profile = peakProfile,
           let observed = profile.averageMinutes(ratio: .oneToFive, tempBracket: bracket)
        {
            return observed
        }
        return activePeakAverageMinutes
            ?? TemperatureCalculator.levainBuildMinutes(kitchenTemp: kitchenTempCelsius)
    }

    // MARK: - Matching

    private static func isOpen(_ step: ScheduleStepSnapshot) -> Bool {
        step.status == .upcoming || step.status == .active
    }

    private static func firstOpen(
        _ stepTypeID: StepTypeID,
        in steps: [ScheduleStepSnapshot]
    ) -> ScheduleStepSnapshot? {
        steps.first { $0.stepTypeID == stepTypeID && isOpen($0) }
    }

    private static func completeOpenFillers(
        in steps: [ScheduleStepSnapshot],
        at time: Date
    ) -> [ScheduleSyncEffect] {
        steps
            .filter { fillerStepTypes.contains($0.stepTypeID) && isOpen($0) }
            .map { .completeStep(index: $0.index, at: time) }
    }
}
