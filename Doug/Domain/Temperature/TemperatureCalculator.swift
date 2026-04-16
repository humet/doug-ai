import Foundation

/// Pure temperature-related calculations for schedule building.
/// No SwiftUI or SwiftData imports — independently testable.
enum TemperatureCalculator {
    /// Base temperature below which yeast activity is negligible (°C).
    static let yeastDormancyThreshold = 4.0

    /// Default adjustment factor per degree Celsius (~7%).
    static let defaultAdjustmentFactor = 0.07

    /// Adjusts a step duration based on actual kitchen temperature vs reference temperature.
    ///
    /// Uses an exponential model: duration × (1 - factor)^(actualTemp - referenceTemp).
    /// Warmer → shorter. Cooler → longer.
    ///
    /// - Parameters:
    ///   - baseDurationMinutes: The step's duration at the reference temperature.
    ///   - referenceTemp: The temperature at which baseDuration was calibrated (°C).
    ///   - actualTemp: The user's actual kitchen temperature (°C).
    ///   - factor: Adjustment per degree (default 0.07 = 7%).
    /// - Returns: Adjusted duration in minutes.
    static func adjustedDuration(
        baseDurationMinutes: Double,
        referenceTemp: Double,
        actualTemp: Double,
        factor: Double = defaultAdjustmentFactor
    ) -> Double {
        let delta = actualTemp - referenceTemp
        let multiplier = pow(1.0 - factor, delta)
        return baseDurationMinutes * multiplier
    }

    /// Estimates levain build time based on kitchen temperature.
    ///
    /// - Parameter kitchenTemp: Kitchen temperature in °C.
    /// - Returns: Estimated levain build time in minutes.
    static func levainBuildMinutes(kitchenTemp: Double) -> Double {
        switch kitchenTemp {
        case 26...: return 240   // 4 hours
        case 22..<26: return 300 // 5 hours
        default: return 360      // 6 hours
        }
    }

    /// Computes the effective duration of a method step, applying temperature
    /// adjustment if the step type is temperature-adjusted.
    ///
    /// - Parameters:
    ///   - step: The method step from the recipe.
    ///   - kitchenTemp: The user's kitchen temperature in °C.
    /// - Returns: Duration in minutes.
    static func effectiveDuration(for step: MethodStep, kitchenTemp: Double) -> Double {
        let stepType = step.stepType

        guard stepType.isTemperatureAdjusted, let refTemp = stepType.referenceTemperatureCelsius else {
            return step.effectiveDuration
        }

        // Special case: levain uses stepped estimates, not exponential
        if step.stepTypeID == .buildLevain {
            return levainBuildMinutes(kitchenTemp: kitchenTemp)
        }

        return adjustedDuration(
            baseDurationMinutes: step.effectiveDuration,
            referenceTemp: refTemp,
            actualTemp: kitchenTemp
        )
    }
}
