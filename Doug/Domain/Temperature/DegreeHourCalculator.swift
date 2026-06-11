import Foundation

/// Calculates accumulated degree-hours from dough temperature readings.
///
/// Degree-hours measure total fermentation energy: (doughTemp - baseTemp) × hours.
/// Uses trapezoidal integration between discrete readings for accuracy.
enum DegreeHourCalculator {
    /// Temperature below which yeast activity is negligible (°C).
    static let baseTempCelsius = 4.0

    /// Calculates accumulated degree-hours from an array of temperature/time pairs.
    ///
    /// Uses trapezoidal integration: for each interval, the average of the two
    /// endpoint temperatures (minus base) is multiplied by the interval duration.
    ///
    /// - Parameters:
    ///   - readings: Array of (timestamp, temperature°C) pairs, need not be sorted.
    ///   - asOf: When later than the last reading, extends the integration from
    ///     the last reading to this date assuming its temperature holds constant.
    ///     Readings are only prompted through the fold window, so without this
    ///     tail the total freezes at the last fold and under-reports.
    /// - Returns: Accumulated degree-hours above base temperature.
    static func accumulatedDegreeHours(
        readings: [(timestamp: Date, temperatureCelsius: Double)],
        extrapolatedTo asOf: Date? = nil
    ) -> Double {
        let sorted = readings.sorted { $0.timestamp < $1.timestamp }
        var total = 0.0

        if sorted.count >= 2 {
            for i in 1 ..< sorted.count {
                let prev = sorted[i - 1]
                let curr = sorted[i]

                let avgTemp = (prev.temperatureCelsius + curr.temperatureCelsius) / 2.0
                let effectiveTemp = max(avgTemp - baseTempCelsius, 0)
                let hours = curr.timestamp.timeIntervalSince(prev.timestamp) / 3600.0

                total += effectiveTemp * hours
            }
        }

        if let asOf, let last = sorted.last, asOf > last.timestamp {
            let effectiveTemp = max(last.temperatureCelsius - baseTempCelsius, 0)
            let hours = asOf.timeIntervalSince(last.timestamp) / 3600.0
            total += effectiveTemp * hours
        }

        return total
    }

    /// Estimates minutes remaining to reach a target degree-hour threshold.
    ///
    /// Assumes the current temperature will hold constant for the remainder.
    ///
    /// - Parameters:
    ///   - currentDegreeHours: Accumulated degree-hours so far.
    ///   - targetDegreeHours: The recipe's target threshold.
    ///   - latestTempCelsius: Most recent dough temperature reading.
    /// - Returns: Estimated minutes remaining, or nil if temperature is too low to estimate.
    static func estimatedMinutesRemaining(
        currentDegreeHours: Double,
        targetDegreeHours: Double,
        latestTempCelsius: Double
    ) -> Double? {
        let effectiveTemp = latestTempCelsius - baseTempCelsius
        guard effectiveTemp > 0 else { return nil }

        let remaining = targetDegreeHours - currentDegreeHours
        guard remaining > 0 else { return 0 }

        let hoursRemaining = remaining / effectiveTemp
        return hoursRemaining * 60
    }

    /// Calculates the progress fraction (0.0–1.0) toward the target.
    static func progress(
        currentDegreeHours: Double,
        targetDegreeHours: Double
    ) -> Double {
        guard targetDegreeHours > 0 else { return 0 }
        return min(currentDegreeHours / targetDegreeHours, 1.0)
    }
}
