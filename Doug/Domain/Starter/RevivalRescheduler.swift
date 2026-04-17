import Foundation

/// Computes schedule-drift deltas for revival feeds.
///
/// A delta means "shift every downstream feed by this many seconds." Zero inside
/// the step's tolerance band; positive when the user runs late; negative when
/// things peak faster than expected (rare for revival, but possible).
enum RevivalRescheduler {
    /// Delta in seconds to cascade to subsequent feeds when the user marks peak.
    ///
    /// - Parameters:
    ///   - scheduledTime: The step's scheduled start.
    ///   - startedAt: When the user actually mixed (nil → fall back to scheduledTime).
    ///   - peakAt: When the user tapped "Mark peak now".
    ///   - expectedPeakMinutes: The target peak time.
    ///   - minPeakMinutes / maxPeakMinutes: Tolerance band; nil → derive as 0.75× / 1.5×.
    /// - Returns: Zero if `peakAt` is inside the tolerance window, otherwise
    ///   `(actualMinutes - expectedPeakMinutes) * 60`.
    static func peakDelta(
        scheduledTime: Date,
        startedAt: Date?,
        peakAt: Date,
        expectedPeakMinutes: Double,
        minPeakMinutes: Double? = nil,
        maxPeakMinutes: Double? = nil
    ) -> TimeInterval {
        let reference = startedAt ?? scheduledTime
        let actualMinutes = peakAt.timeIntervalSince(reference) / 60
        let min = minPeakMinutes ?? expectedPeakMinutes * 0.75
        let max = maxPeakMinutes ?? expectedPeakMinutes * 1.5

        if actualMinutes >= min, actualMinutes <= max {
            return 0
        }
        return (actualMinutes - expectedPeakMinutes) * 60
    }

    /// Delta in seconds to cascade when the user taps "I've mixed" late.
    ///
    /// A small grace window (default 30 min) absorbs minor tardiness without
    /// re-planning. Beyond the grace, the delta is the excess lateness.
    static func startDelta(
        scheduledTime: Date,
        startedAt: Date,
        graceMinutes: Double = 30
    ) -> TimeInterval {
        let lateSeconds = startedAt.timeIntervalSince(scheduledTime)
        let graceSeconds = graceMinutes * 60
        if lateSeconds <= graceSeconds {
            return 0
        }
        return lateSeconds - graceSeconds
    }
}
