import Foundation

/// Generates a revival feeding plan for a neglected starter.
///
/// Creates a sequence of 2-3 consecutive feeds at a tight ratio (1:2:2)
/// spaced by expected peak times, respecting availability.
enum RevivalPlanGenerator {
    /// Default revival feed ratio.
    static let revivalRatio = (starter: 1, flour: 2, water: 2)

    /// Number of revival feeds.
    static let feedCount = 3

    /// Expected peak time per revival feed in minutes (decreasing as starter strengthens).
    static let expectedPeakMinutes: [Double] = [360, 300, 240] // 6h, 5h, 4h

    /// Generates a revival plan: an array of scheduled revival feeds.
    ///
    /// - Parameters:
    ///   - startTime: When to begin the revival.
    ///   - availability: Daily available hours.
    ///   - windows: Unavailable windows.
    ///   - calendar: Calendar for date math.
    /// - Returns: Array of revival feed steps with scheduled times.
    static func generate(
        startTime: Date,
        availability: AvailabilityInput,
        windows: [WindowInput],
        calendar: Calendar = .current
    ) -> [RevivalFeedPlan] {
        var feeds: [RevivalFeedPlan] = []
        var cursor = startTime

        for i in 0..<feedCount {
            // Snap to available time
            let feedTime = FeedScheduler.nextFeedTime(
                lastFeedTime: nil,
                cycleDays: 0,
                upcomingBakeStart: nil,
                availability: availability,
                windows: windows,
                now: cursor,
                calendar: calendar
            ) ?? cursor

            let peakMinutes = i < expectedPeakMinutes.count
                ? expectedPeakMinutes[i]
                : expectedPeakMinutes.last ?? 300

            feeds.append(RevivalFeedPlan(
                sequenceIndex: i,
                scheduledTime: feedTime,
                expectedPeakMinutes: peakMinutes,
                ratioStarter: revivalRatio.starter,
                ratioFlour: revivalRatio.flour,
                ratioWater: revivalRatio.water
            ))

            // Next feed starts after expected peak + 30 min buffer
            cursor = feedTime.addingTimeInterval((peakMinutes + 30) * 60)
        }

        return feeds
    }

    /// Estimates when the starter will be bake-ready after completing revival.
    static func estimatedBakeReadyDate(
        startTime: Date,
        calendar: Calendar = .current
    ) -> Date {
        let totalMinutes = expectedPeakMinutes.reduce(0, +) + Double(feedCount - 1) * 30
        return startTime.addingTimeInterval(totalMinutes * 60)
    }
}

/// A planned revival feed step (domain output, not SwiftData).
struct RevivalFeedPlan: Sendable {
    let sequenceIndex: Int
    let scheduledTime: Date
    let expectedPeakMinutes: Double
    let ratioStarter: Int
    let ratioFlour: Int
    let ratioWater: Int
}
