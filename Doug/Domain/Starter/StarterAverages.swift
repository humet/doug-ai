import Foundation

/// Single home for recomputing a starter's time-to-peak averages from its feed
/// history. Both the Starter tab and the schedule's step side effects must use
/// this — a running `(avg + new) / 2` on one path would drift from the full
/// recompute on the other.
enum StarterAverages {
    struct Result: Equatable {
        /// Average across all feed intents, or nil when no plausible peaks exist.
        let averageTimeToPeakMinutes: Double?
        /// Average across activation feeds only — what the scheduler plans with.
        let activePeakAverageMinutes: Double?
    }

    /// Averages over plausible readings only (see
    /// `StarterPeakProfile.plausibleTimeToPeakRange`) so one bad entry can't
    /// corrupt schedule estimates.
    static func recompute(feedLogs: [FeedLogInput]) -> Result {
        let allPeaks = feedLogs
            .compactMap(\.timeToPeakMinutes)
            .filter(StarterPeakProfile.isPlausibleTimeToPeak)

        let activationPeaks = feedLogs
            .filter { $0.feedIntent == .activation }
            .compactMap(\.timeToPeakMinutes)
            .filter(StarterPeakProfile.isPlausibleTimeToPeak)

        return Result(
            averageTimeToPeakMinutes: average(of: allPeaks),
            activePeakAverageMinutes: average(of: activationPeaks)
        )
    }

    private static func average(of values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }
}
