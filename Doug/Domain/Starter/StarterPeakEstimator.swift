import Foundation

enum StarterPeakEstimator {
    /// Estimates when an unobserved feed peaked ("it peaked while I slept").
    /// Fallback chain: activation average → overall average → temperature
    /// default. The estimate is clamped to no earlier than the plausible
    /// minimum rise after the feed and never in the future.
    static func estimatedPeakDate(
        feedTimestamp: Date,
        activePeakAverageMinutes: Double?,
        averageTimeToPeakMinutes: Double?,
        kitchenTempCelsius: Double,
        now: Date = Date()
    ) -> Date {
        let minutes = activePeakAverageMinutes
            ?? averageTimeToPeakMinutes
            ?? TemperatureCalculator.levainBuildMinutes(kitchenTemp: kitchenTempCelsius)
        let earliestPlausible = feedTimestamp.addingTimeInterval(
            StarterPeakProfile.plausibleTimeToPeakRange.lowerBound * 60
        )
        let estimate = feedTimestamp.addingTimeInterval(minutes * 60)
        return min(max(estimate, earliestPlausible), now)
    }
}
