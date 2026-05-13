import Foundation

extension ScheduleBuilder {
    /// Computes the viable bread-ready time range for a recipe and availability.
    ///
    /// - **Earliest**: wake-up time + post-Cold-Retard steps (Preheat + Bake) + Cold Retard minimum.
    /// - **Latest**: sleep time + Cold Retard max + post-Cold-Retard steps, capped so morning steps
    ///   finish before the next sleep window.
    static func viableRange(
        recipe: Recipe,
        kitchenTemperatureCelsius: Double,
        availability: AvailabilityInput,
        windows: [WindowInput] = [],
        referenceDate: Date = Date(),
        calendar: Calendar = .current,
        peakProfile: StarterPeakProfile? = nil
    ) -> ClosedRange<Date>? {
        let method = recipe.method

        guard let coldRetardMethod = method.first(where: { $0.stepTypeID == .coldRetard }),
              let flexRange = coldRetardMethod.effectiveFlexRange
        else {
            return nil
        }

        // Sum durations of steps after Cold Retard (Preheat + Bake and sub-steps)
        let coldRetardIndex = method.firstIndex(where: { $0.stepTypeID == .coldRetard })!
        let postColdRetardSteps = method[(coldRetardIndex + 1)...]
        let postColdRetardMinutes = postColdRetardSteps.reduce(0.0) { total, step in
            total + TemperatureCalculator.effectiveDuration(
                for: step,
                kitchenTemp: kitchenTemperatureCelsius,
                peakProfile: peakProfile
            )
        }

        // Sum durations of hands-on steps before and including Shape
        // (everything before Cold Retard that needs to fit before sleep)
        let preColdRetardSteps = method[..<coldRetardIndex]
        let preColdRetardMinutes = preColdRetardSteps.reduce(0.0) { total, step in
            total + TemperatureCalculator.effectiveDuration(
                for: step,
                kitchenTemp: kitchenTemperatureCelsius,
                peakProfile: peakProfile
            )
        }

        // Find the next occurrence of wake-up and sleep times from the reference date
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: referenceDate)!
        let tomorrowStart = calendar.startOfDay(for: tomorrow)

        guard let wakeUp = calendar.date(
            bySettingHour: availability.startHour,
            minute: availability.startMinute,
            second: 0,
            of: tomorrowStart
        ),
            let sleepTime = calendar.date(
                bySettingHour: availability.endHour,
                minute: availability.endMinute,
                second: 0,
                of: referenceDate
            )
        else {
            return nil
        }

        // Earliest: morning steps must start after wake-up
        // Cold Retard at minimum duration ends just in time for preheat
        let earliestBreadReady = wakeUp.addingTimeInterval(postColdRetardMinutes * 60)

        // Latest: all pre-Cold-Retard steps must finish by sleep time
        // Cold Retard starts at sleep time, runs at max flex
        let latestColdRetardStart = sleepTime
        let latestColdRetardEnd = latestColdRetardStart.addingTimeInterval(flexRange.upperBound * 60)
        let latestBreadReady = latestColdRetardEnd.addingTimeInterval(postColdRetardMinutes * 60)

        // Also verify that pre-Cold-Retard steps actually fit before sleep
        let earliestPreColdRetardStart = sleepTime.addingTimeInterval(-preColdRetardMinutes * 60)
        guard earliestPreColdRetardStart >= wakeUp.addingTimeInterval(-24 * 60 * 60) else {
            return nil
        }

        // Ensure morning steps don't extend past the next sleep window
        let nextSleep = calendar.date(
            bySettingHour: availability.endHour,
            minute: availability.endMinute,
            second: 0,
            of: tomorrowStart
        ) ?? tomorrowStart
        let cappedLatest = min(latestBreadReady, nextSleep)

        guard earliestBreadReady <= cappedLatest else { return nil }

        return earliestBreadReady ... cappedLatest
    }
}
