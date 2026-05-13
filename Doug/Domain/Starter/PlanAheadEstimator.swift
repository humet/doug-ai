import Foundation

enum PlanAheadEstimator {
    struct Estimate {
        let activateBy: Date
        let levainStartTime: Date
        let breadReadyTime: Date
        let activationDurationMinutes: Double
    }

    enum Result {
        case feasible(Estimate)
        case conflict(message: String, suggestedAlternativeTime: Date?)
        case noAvailabilityConfigured(Estimate)
    }

    static func estimate(
        recipe: Recipe,
        targetBreadReadyTime: Date,
        kitchenTemperatureCelsius: Double,
        availability: AvailabilityInput?,
        unavailableWindows: [WindowInput],
        peakProfile: StarterPeakProfile?,
        activePeakAverageMinutes: Double?,
        calendar: Calendar = .current
    ) -> Result {
        let peakDuration = activePeakAverageMinutes
            ?? TemperatureCalculator.levainBuildMinutes(kitchenTemp: kitchenTemperatureCelsius)

        guard let avail = availability else {
            return noAvailabilityFallback(
                recipe: recipe,
                targetBreadReadyTime: targetBreadReadyTime,
                kitchenTemperatureCelsius: kitchenTemperatureCelsius,
                peakProfile: peakProfile,
                peakDuration: peakDuration
            )
        }

        let input = ScheduleBuilderInput(
            recipe: recipe,
            targetBreadReadyTime: targetBreadReadyTime,
            kitchenTemperatureCelsius: kitchenTemperatureCelsius,
            availability: avail,
            unavailableWindows: unavailableWindows,
            calendar: calendar,
            peakProfile: peakProfile,
            levainContext: nil
        )

        let scheduleResult = ScheduleBuilder.build(input)

        switch scheduleResult {
        case let .conflict(conflict):
            return .conflict(
                message: conflict.message,
                suggestedAlternativeTime: conflict.suggestedAlternativeTime
            )

        case let .success(steps):
            guard let levainStart = steps.first?.startTime else {
                return .conflict(
                    message: "Could not determine schedule start time.",
                    suggestedAlternativeTime: nil
                )
            }

            let rawActivateBy = levainStart.addingTimeInterval(-peakDuration * 60)

            let activateBy = snapActivationBackward(
                candidate: rawActivateBy,
                peakDuration: peakDuration,
                levainStart: levainStart,
                availability: avail,
                windows: unavailableWindows,
                calendar: calendar
            )

            guard let activateBy else {
                return .conflict(
                    message: "Can't fit starter activation into your available hours before the levain build.",
                    suggestedAlternativeTime: nil
                )
            }

            return .feasible(Estimate(
                activateBy: activateBy,
                levainStartTime: levainStart,
                breadReadyTime: targetBreadReadyTime,
                activationDurationMinutes: peakDuration
            ))
        }
    }

    // MARK: - Activation Placement

    /// Finds an available slot for the activation feed, searching backward from `candidate`.
    ///
    /// The activation feed is a brief hands-on action (~5 min) followed by a passive peak wait.
    /// The hands-on moment must land in an available window, and the peak must complete
    /// before `levainStart`.
    private static func snapActivationBackward(
        candidate: Date,
        peakDuration: Double,
        levainStart: Date,
        availability: AvailabilityInput,
        windows: [WindowInput],
        calendar: Calendar
    ) -> Date? {
        let searchStart = calendar.date(byAdding: .day, value: -2, to: candidate) ?? candidate
        let blocks = AvailabilityResolver.resolve(
            from: searchStart,
            to: levainStart,
            availability: availability,
            windows: windows,
            calendar: calendar
        )

        let feedBuffer: TimeInterval = 10 * 60

        // Try the candidate first
        if isClearAndFits(
            time: candidate, feedBuffer: feedBuffer, peakDuration: peakDuration,
            levainStart: levainStart, blocks: blocks
        ) {
            return candidate
        }

        // Search backward in 30-minute increments
        var probe = candidate.addingTimeInterval(-30 * 60)
        while probe > searchStart {
            if isClearAndFits(
                time: probe, feedBuffer: feedBuffer, peakDuration: peakDuration,
                levainStart: levainStart, blocks: blocks
            ) {
                return probe
            }
            probe = probe.addingTimeInterval(-30 * 60)
        }

        // Last resort: search forward from candidate (activation may push schedule later)
        if let forwardSlot = FeedScheduler.snapToAvailableTime(
            candidate: candidate,
            availability: availability,
            windows: windows,
            calendar: calendar
        ), forwardSlot.addingTimeInterval(peakDuration * 60) <= levainStart {
            return forwardSlot
        }

        return nil
    }

    private static func isClearAndFits(
        time: Date,
        feedBuffer: TimeInterval,
        peakDuration: Double,
        levainStart: Date,
        blocks: [UnavailableBlock]
    ) -> Bool {
        let feedEnd = time.addingTimeInterval(feedBuffer)
        let peakEnd = time.addingTimeInterval(peakDuration * 60)
        return AvailabilityResolver.overlaps(start: time, end: feedEnd, blocks: blocks).isEmpty
            && peakEnd <= levainStart
    }

    // MARK: - Fallback

    private static func noAvailabilityFallback(
        recipe: Recipe,
        targetBreadReadyTime: Date,
        kitchenTemperatureCelsius: Double,
        peakProfile: StarterPeakProfile?,
        peakDuration: Double
    ) -> Result {
        let recipeDuration = EarliestBakeEstimator.recipeDurationMinutes(
            recipe: recipe,
            kitchenTempC: kitchenTemperatureCelsius,
            peakProfile: peakProfile
        )
        let levainStart = targetBreadReadyTime.addingTimeInterval(-recipeDuration * 60)
        let activateBy = levainStart.addingTimeInterval(-peakDuration * 60)

        return .noAvailabilityConfigured(Estimate(
            activateBy: activateBy,
            levainStartTime: levainStart,
            breadReadyTime: targetBreadReadyTime,
            activationDurationMinutes: peakDuration
        ))
    }
}
