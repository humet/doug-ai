import Foundation

enum EarliestBakeEstimator {
    struct Estimate {
        let earliestBreadReady: Date
        let activationLeadMinutes: Double
        let scheduleDurationMinutes: Double
        let breakdown: String
    }

    static func estimate(
        lifecycleState: StarterLifecycleState,
        stateChangedAt: Date,
        lastActivationFeed: FeedLogInput?,
        activePeakAverage: Double?,
        kitchenTempC: Double,
        scheduleDurationMinutes: Double,
        now: Date = Date()
    ) -> Estimate {
        let lead = activationLeadMinutes(
            lifecycleState: lifecycleState,
            stateChangedAt: stateChangedAt,
            lastActivationFeed: lastActivationFeed,
            activePeakAverage: activePeakAverage,
            kitchenTempC: kitchenTempC,
            now: now
        )

        let earliest = now.addingTimeInterval((lead + scheduleDurationMinutes) * 60)
        let breakdown = formatBreakdown(activationMinutes: lead, scheduleMinutes: scheduleDurationMinutes)

        return Estimate(
            earliestBreadReady: earliest,
            activationLeadMinutes: lead,
            scheduleDurationMinutes: scheduleDurationMinutes,
            breakdown: breakdown
        )
    }

    static func activationLeadMinutes(
        lifecycleState: StarterLifecycleState,
        stateChangedAt _: Date,
        lastActivationFeed: FeedLogInput?,
        activePeakAverage: Double?,
        kitchenTempC: Double,
        now: Date = Date()
    ) -> Double {
        switch lifecycleState {
        case .active:
            return 0

        case .activating:
            if let feed = lastActivationFeed, feed.timeToPeakMinutes == nil {
                let expectedPeak = activePeakAverage
                    ?? TemperatureCalculator.levainBuildMinutes(kitchenTemp: kitchenTempC)
                let elapsed = now.timeIntervalSince(feed.timestamp) / 60.0
                return max(0, expectedPeak - elapsed)
            }
            return 0

        case .dormant:
            return activePeakAverage
                ?? TemperatureCalculator.levainBuildMinutes(kitchenTemp: kitchenTempC)

        case .reviving:
            return activePeakAverage
                ?? TemperatureCalculator.levainBuildMinutes(kitchenTemp: kitchenTempC)
        }
    }

    /// Sums temperature-adjusted durations for all method steps in a recipe.
    static func recipeDurationMinutes(
        recipe: Recipe,
        kitchenTempC: Double,
        peakProfile: StarterPeakProfile? = nil
    ) -> Double {
        recipe.method.reduce(0) { total, step in
            total + TemperatureCalculator.effectiveDuration(
                for: step,
                kitchenTemp: kitchenTempC,
                peakProfile: peakProfile
            )
        }
    }

    private static func formatBreakdown(activationMinutes: Double, scheduleMinutes: Double) -> String {
        let activationText = activationMinutes > 0
            ? "~\(formatHours(activationMinutes)) activation + "
            : ""
        return "\(activationText)~\(formatHours(scheduleMinutes)) bake"
    }

    private static func formatHours(_ minutes: Double) -> String {
        let hours = minutes / 60
        if hours < 1 {
            return "\(Int(minutes))m"
        }
        let h = Int(hours)
        let m = Int(minutes.truncatingRemainder(dividingBy: 60))
        return m > 0 ? "\(h)h \(m)m" : "\(h)h"
    }
}
