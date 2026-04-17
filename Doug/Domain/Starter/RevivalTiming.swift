import Foundation

/// Answers "will this peak fall while I'm asleep?" and suggests a delayed
/// mix time so peak lands inside the user's available hours.
enum RevivalTiming {
    /// True if the expected peak for this start time overlaps any unavailable block.
    static func peakFallsInUnavailable(
        startTime: Date,
        expectedPeakMinutes: Double,
        availability: AvailabilityInput,
        windows: [WindowInput],
        calendar: Calendar = .current
    ) -> Bool {
        let peak = startTime.addingTimeInterval(expectedPeakMinutes * 60)
        return isInsideUnavailable(
            instant: peak,
            availability: availability,
            windows: windows,
            calendar: calendar
        )
    }

    /// Suggests a later start time so the peak lands inside the user's available hours.
    ///
    /// Returns `nil` if `currentTime` is already a safe start. Probes forward in 30-minute
    /// steps up to 48 hours; also requires the suggested start itself to be in an available
    /// slot (so the user can actually mix then).
    static func suggestedStartTime(
        currentTime: Date,
        expectedPeakMinutes: Double,
        availability: AvailabilityInput,
        windows: [WindowInput],
        calendar: Calendar = .current
    ) -> Date? {
        if !peakFallsInUnavailable(
            startTime: currentTime,
            expectedPeakMinutes: expectedPeakMinutes,
            availability: availability,
            windows: windows,
            calendar: calendar
        ) {
            return nil
        }

        let horizon = currentTime.addingTimeInterval(48 * 3600)
        var probe = currentTime.addingTimeInterval(30 * 60)

        while probe < horizon {
            let mixOk = !isInsideUnavailable(
                instant: probe,
                availability: availability,
                windows: windows,
                calendar: calendar
            )
            let peakOk = !peakFallsInUnavailable(
                startTime: probe,
                expectedPeakMinutes: expectedPeakMinutes,
                availability: availability,
                windows: windows,
                calendar: calendar
            )
            if mixOk && peakOk {
                return probe
            }
            probe = probe.addingTimeInterval(30 * 60)
        }
        return nil
    }

    // MARK: - Private

    /// True if `instant` overlaps any unavailable block in a small buffer around it.
    private static func isInsideUnavailable(
        instant: Date,
        availability: AvailabilityInput,
        windows: [WindowInput],
        calendar: Calendar
    ) -> Bool {
        let blocks = AvailabilityResolver.resolve(
            from: instant.addingTimeInterval(-3600),
            to: instant.addingTimeInterval(3600),
            availability: availability,
            windows: windows,
            calendar: calendar
        )
        let end = instant.addingTimeInterval(60)
        return !AvailabilityResolver.overlaps(start: instant, end: end, blocks: blocks).isEmpty
    }
}
