import Foundation

/// Lays out the feeding plan for a starter that does not exist yet.
///
/// Sibling to `RevivalPlanGenerator`, which handles an existing starter. Both
/// walk forward from a start time, temperature-adjust the waits, and snap every
/// hands-on feed into the user's available hours via `FeedScheduler`.
///
/// The output is only a baseline. Real timelines vary from under a week to over
/// three, so `StarterEstablishProgress` reshapes the plan from what the user
/// actually reports seeing.
enum StarterOriginPlanner {
    /// Kitchen temperature the base waits are calibrated for.
    static let referenceKitchenTempC = 22.0

    /// Honest range to show in the route picker, in days.
    static func estimatedDays(for origin: StarterOrigin) -> ClosedRange<Int> {
        switch origin {
        case .fromScratch: 7 ... 21
        case .driedCulture, .shopKit: 3 ... 6
        case .freshGift: 1 ... 2
        }
    }

    /// The flour that gives a new culture the best start. Wholemeal and rye
    /// carry far more wild yeast and mineral content than white.
    static func recommendedFlour(for origin: StarterOrigin) -> String {
        switch origin {
        case .fromScratch, .driedCulture, .shopKit: "whole wheat"
        case .freshGift: "white"
        }
    }

    /// Sensible default starting weight for the route's seed measurement.
    static func defaultSeedGrams(for origin: StarterOrigin) -> Double {
        switch origin {
        case .fromScratch: 50
        case .driedCulture, .shopKit: 5
        case .freshGift: 30
        }
    }

    // MARK: - Planning

    static func plan(_ input: StarterOriginPlanInput) -> [StarterProgramStep] {
        let environment = input.environment
        let blueprints = StarterOriginBlueprints.blueprints(for: input.origin, seedGrams: input.seedGrams)
        var steps: [StarterProgramStep] = []
        var cursor = input.startTime

        for (index, blueprint) in blueprints.enumerated() {
            // The first step happens when the user says it does; later steps
            // snap into available hours so they can actually be done.
            let scheduled = index == 0 ? cursor : snapped(cursor, environment: environment)

            let shape = blueprint.shape
            let peak = adjusted(shape.peak, temperatureSensitive: true, environment: environment)
            let cadence = adjusted(
                blueprint.cadenceMinutes,
                temperatureSensitive: shape.cadenceIsTemperatureSensitive,
                environment: environment
            )

            steps.append(step(
                at: scheduled,
                index: index,
                planStart: input.startTime,
                kind: blueprint.kind,
                phase: blueprint.phase,
                shape: shape,
                peak: peak,
                cadence: cadence,
                grams: blueprint.grams,
                ratio: blueprint.ratio,
                environment: environment
            ))

            cursor = scheduled.addingTimeInterval(cadence * 60)
        }

        return steps
    }

    /// Estimated moment the starter becomes usable: the last step plus its wait.
    static func estimatedReadyDate(from steps: [StarterProgramStep]) -> Date? {
        guard let last = steps.last else { return nil }
        return last.scheduledTime.addingTimeInterval(last.expectedPeakMinutes * 60)
    }

    /// Extra steps appended when a plan needs stretching — a stalled culture
    /// that needs more time, or a confirming feed that missed its window.
    static func extensionSteps(
        _ request: StarterPlanExtension,
        environment: StarterPlanEnvironment
    ) -> [StarterProgramStep] {
        guard request.count > 0 else { return [] }

        let template = request.template
        let kind = request.kind ?? template.kind
        let phase = request.phase ?? template.phase
        let shape = StepShape.forKind(kind)

        let peak = adjusted(shape.peak, temperatureSensitive: true, environment: environment)
        let cadence = adjusted(
            shape.cadence,
            temperatureSensitive: shape.cadenceIsTemperatureSensitive,
            environment: environment
        )

        var steps: [StarterProgramStep] = []
        var cursor = request.startingAt

        for offset in 0 ..< request.count {
            let scheduled = snapped(cursor, environment: environment)
            steps.append(step(
                at: scheduled,
                index: template.sequenceIndex + 1 + offset,
                planStart: request.planStartDate,
                kind: kind,
                phase: phase,
                shape: shape,
                peak: peak,
                cadence: cadence,
                grams: FeedGrams(
                    retain: template.retainStarterGrams,
                    flour: template.addFlourGrams,
                    water: template.addWaterGrams
                ),
                ratio: FeedRatio(
                    starter: template.ratioStarter,
                    flour: template.ratioFlour,
                    water: template.ratioWater
                ),
                environment: environment
            ))
            cursor = scheduled.addingTimeInterval(cadence * 60)
        }

        return steps
    }

    // MARK: - Step Assembly

    // swiftlint:disable:next function_parameter_count
    private static func step(
        at scheduled: Date,
        index: Int,
        planStart: Date,
        kind: StarterStepKind,
        phase: StarterEstablishPhase,
        shape: StepShape,
        peak: Double,
        cadence: Double,
        grams: FeedGrams,
        ratio: FeedRatio,
        environment: StarterPlanEnvironment
    ) -> StarterProgramStep {
        StarterProgramStep(
            sequenceIndex: index,
            dayNumber: dayNumber(of: scheduled, planStart: planStart, calendar: environment.calendar),
            kind: kind,
            phase: phase,
            scheduledTime: scheduled,
            expectsPeak: kind.expectsPeak,
            // A step with no peak still needs a wait to display, so fall back
            // to its cadence.
            expectedPeakMinutes: kind.expectsPeak ? peak : cadence,
            minPeakMinutes: kind.expectsPeak ? peak * shape.minFactor : nil,
            maxPeakMinutes: kind.expectsPeak ? peak * shape.maxFactor : nil,
            retainStarterGrams: grams.retain,
            addFlourGrams: grams.flour,
            addWaterGrams: grams.water,
            ratioStarter: ratio.starter,
            ratioFlour: ratio.flour,
            ratioWater: ratio.water
        )
    }

    // MARK: - Helpers

    private static func snapped(
        _ candidate: Date,
        environment: StarterPlanEnvironment
    ) -> Date {
        FeedScheduler.snapToAvailableTime(
            candidate: candidate,
            availability: environment.availability,
            windows: environment.windows,
            calendar: environment.calendar
        ) ?? candidate
    }

    private static func adjusted(
        _ minutes: Double,
        temperatureSensitive: Bool,
        environment: StarterPlanEnvironment
    ) -> Double {
        guard temperatureSensitive, minutes > 0 else { return minutes }
        return TemperatureCalculator.adjustedDuration(
            baseDurationMinutes: minutes,
            referenceTemp: referenceKitchenTempC,
            actualTemp: environment.kitchenTempC
        )
    }

    /// Calendar day of the plan, counting the start day as day 1.
    static func dayNumber(
        of instant: Date,
        planStart: Date,
        calendar: Calendar = .current
    ) -> Int {
        let from = calendar.startOfDay(for: planStart)
        let to = calendar.startOfDay(for: instant)
        let days = calendar.dateComponents([.day], from: from, to: to).day ?? 0
        return max(days + 1, 1)
    }
}
