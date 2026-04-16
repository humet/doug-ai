import Foundation

/// Suggests the next feed time for a starter, respecting availability and upcoming bakes.
enum FeedScheduler {
    /// Calculates the next suggested feed time.
    ///
    /// Logic:
    /// 1. If a bake is upcoming, work backwards from the levain build time
    ///    and suggest a maintenance feed that keeps the starter active.
    /// 2. Otherwise, schedule based on the maintenance cycle from the last feed.
    /// 3. Shift the time to avoid unavailable windows.
    ///
    /// - Parameters:
    ///   - lastFeedTime: When the starter was last fed.
    ///   - cycleDays: Maintenance cycle interval in days.
    ///   - upcomingBakeStart: The start of the next planned bake's levain build (if any).
    ///   - availability: Daily available hours.
    ///   - windows: Unavailable windows.
    ///   - now: Current date.
    ///   - calendar: Calendar for date math.
    /// - Returns: Suggested feed time, or nil if none can be determined.
    static func nextFeedTime(
        lastFeedTime: Date?,
        cycleDays: Double,
        upcomingBakeStart: Date?,
        availability: AvailabilityInput,
        windows: [WindowInput],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Date? {
        let candidateTime: Date

        if let bakeStart = upcomingBakeStart {
            // Work backwards: feed 1-2 days before the bake's levain build
            let feedBeforeBake = calendar.date(byAdding: .day, value: -2, to: bakeStart) ?? bakeStart
            candidateTime = max(feedBeforeBake, now)
        } else if let lastFeed = lastFeedTime {
            // Next feed based on maintenance cycle
            let nextCycle = lastFeed.addingTimeInterval(cycleDays * 86400)
            candidateTime = max(nextCycle, now)
        } else {
            // No history — suggest now
            candidateTime = now
        }

        // Snap to a convenient time within available hours
        return snapToAvailableTime(
            candidate: candidateTime,
            availability: availability,
            windows: windows,
            calendar: calendar
        )
    }

    /// Snaps a candidate time to the nearest available slot.
    private static func snapToAvailableTime(
        candidate: Date,
        availability: AvailabilityInput,
        windows: [WindowInput],
        calendar: Calendar
    ) -> Date? {
        let blocks = AvailabilityResolver.resolve(
            from: candidate,
            to: calendar.date(byAdding: .day, value: 2, to: candidate) ?? candidate,
            availability: availability,
            windows: windows,
            calendar: calendar
        )

        // If the candidate is clear, use it
        let candidateEnd = candidate.addingTimeInterval(10 * 60) // 10 min buffer
        if AvailabilityResolver.overlaps(start: candidate, end: candidateEnd, blocks: blocks).isEmpty {
            return candidate
        }

        // Find the next clear slot after the candidate
        var probe = candidate
        let limit = calendar.date(byAdding: .day, value: 2, to: candidate) ?? candidate
        while probe < limit {
            let probeEnd = probe.addingTimeInterval(10 * 60)
            if AvailabilityResolver.overlaps(start: probe, end: probeEnd, blocks: blocks).isEmpty {
                return probe
            }
            probe = probe.addingTimeInterval(30 * 60) // check every 30 min
        }

        return nil
    }
}
