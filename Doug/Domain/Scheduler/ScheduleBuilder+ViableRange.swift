import Foundation

extension ScheduleBuilder {
    static func viableRange(
        recipe: Recipe,
        kitchenTemperatureCelsius: Double,
        availability: AvailabilityInput,
        windows _: [WindowInput] = [],
        earliestStartTime: Date? = nil,
        referenceDate: Date = Date(),
        calendar: Calendar = .current,
        peakProfile: StarterPeakProfile? = nil
    ) -> ClosedRange<Date>? {
        let effectiveStart = earliestStartTime ?? referenceDate
        let method = recipe.method
        let hasColdRetard = method.contains { $0.stepTypeID.isColdRetard }

        if hasColdRetard {
            return overnightViableRange(
                method: method,
                kitchenTemperatureCelsius: kitchenTemperatureCelsius,
                availability: availability,
                earliestStart: effectiveStart,
                referenceDate: referenceDate,
                calendar: calendar,
                peakProfile: peakProfile
            )
        } else {
            return sameDayViableRange(
                method: method,
                kitchenTemperatureCelsius: kitchenTemperatureCelsius,
                availability: availability,
                earliestStart: effectiveStart,
                referenceDate: referenceDate,
                calendar: calendar,
                peakProfile: peakProfile
            )
        }
    }

    // MARK: - Overnight (Cold Retard)

    private static func overnightViableRange(
        method: [MethodStep],
        kitchenTemperatureCelsius: Double,
        availability: AvailabilityInput,
        earliestStart: Date,
        referenceDate: Date,
        calendar: Calendar,
        peakProfile: StarterPeakProfile?
    ) -> ClosedRange<Date>? {
        guard let coldRetardMethod = method.first(where: { $0.stepTypeID.isColdRetard }),
              let flexRange = coldRetardMethod.effectiveFlexRange
        else {
            return nil
        }

        let coldRetardIndex = method.firstIndex(where: { $0.stepTypeID.isColdRetard })!
        let postColdRetardSteps = method[(coldRetardIndex + 1)...]
        let postColdRetardMinutes = postColdRetardSteps.reduce(0.0) { total, step in
            total + TemperatureCalculator.effectiveDuration(
                for: step,
                kitchenTemp: kitchenTemperatureCelsius,
                peakProfile: peakProfile
            )
        }

        let preColdRetardSteps = method[..<coldRetardIndex]
        let preColdRetardMinutes = preColdRetardSteps.reduce(0.0) { total, step in
            total + TemperatureCalculator.effectiveDuration(
                for: step,
                kitchenTemp: kitchenTemperatureCelsius,
                peakProfile: peakProfile
            )
        }

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

        let preColdRetardStart = max(
            sleepTime.addingTimeInterval(-preColdRetardMinutes * 60),
            earliestStart
        )
        let coldRetardStart = preColdRetardStart.addingTimeInterval(preColdRetardMinutes * 60)
        let minColdRetardEnd = coldRetardStart.addingTimeInterval(flexRange.lowerBound * 60)
        let effectiveWakeUp = max(wakeUp, minColdRetardEnd)

        let earliestBreadReady = effectiveWakeUp.addingTimeInterval(postColdRetardMinutes * 60)

        let latestColdRetardStart = sleepTime
        let latestColdRetardEnd = latestColdRetardStart.addingTimeInterval(flexRange.upperBound * 60)
        let latestBreadReady = latestColdRetardEnd.addingTimeInterval(postColdRetardMinutes * 60)

        guard preColdRetardStart >= wakeUp.addingTimeInterval(-24 * 60 * 60) else {
            return nil
        }

        let nextSleep = calendar.date(
            bySettingHour: availability.endHour,
            minute: availability.endMinute,
            second: 0,
            of: tomorrowStart
        ) ?? tomorrowStart
        // Bread retards (≤18h) always finish by tomorrow night, but a multi-day
        // retard (pizza balls, up to 72h) can legitimately end days out — cap at
        // end-of-availability on the day the longest retard would finish, not
        // at tomorrow's.
        let lastDay = calendar.startOfDay(for: latestBreadReady)
        let lastSleep = calendar.date(
            bySettingHour: availability.endHour,
            minute: availability.endMinute,
            second: 0,
            of: lastDay
        ) ?? latestBreadReady
        let cappedLatest = min(latestBreadReady, max(nextSleep, lastSleep))

        guard earliestBreadReady <= cappedLatest else { return nil }

        return earliestBreadReady ... cappedLatest
    }

    // MARK: - Same-Day (No Cold Retard)

    private static func sameDayViableRange(
        method: [MethodStep],
        kitchenTemperatureCelsius: Double,
        availability: AvailabilityInput,
        earliestStart: Date,
        referenceDate: Date,
        calendar: Calendar,
        peakProfile: StarterPeakProfile?
    ) -> ClosedRange<Date>? {
        var totalMinMinutes = 0.0
        var totalMaxMinutes = 0.0

        for step in method {
            if step.stepType.classification == .passiveFlexible,
               let flexRange = step.effectiveFlexRange
            {
                totalMinMinutes += flexRange.lowerBound
                totalMaxMinutes += flexRange.upperBound
            } else {
                let duration = TemperatureCalculator.effectiveDuration(
                    for: step,
                    kitchenTemp: kitchenTemperatureCelsius,
                    peakProfile: peakProfile
                )
                totalMinMinutes += duration
                totalMaxMinutes += duration
            }
        }

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
                of: tomorrowStart
            )
        else {
            return nil
        }

        let effectiveStart = max(wakeUp, earliestStart)
        let earliestReady = effectiveStart.addingTimeInterval(totalMinMinutes * 60)
        let latestReady = min(
            sleepTime,
            effectiveStart.addingTimeInterval(totalMaxMinutes * 60)
        )

        guard earliestReady <= latestReady else { return nil }

        return earliestReady ... latestReady
    }
}
