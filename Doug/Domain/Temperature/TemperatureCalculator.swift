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
        case 26...: 240 // 4 hours
        case 22 ..< 26: 300 // 5 hours
        default: 360 // 6 hours
        }
    }

    static func fridgeWarmUpMinutes(kitchenTempCelsius: Double) -> Double {
        switch kitchenTempCelsius {
        case 26...: 60
        case 22 ..< 26: 90
        default: 120
        }
    }

    /// Standard levain-build ratio assumed for personalised peak-time lookups.
    static let levainBuildRatio: FeedRatioBucket = .oneToFive

    /// Time constant for dough cooling/warming toward ambient (minutes).
    /// ~75 min for a typical 800g–1kg dough mass in a home kitchen.
    static let doughThermalTimeConstant = 75.0

    /// Calculates the recommended water temperature to hit the desired dough
    /// temperature (DDT).
    ///
    /// When `restMinutes` is provided (e.g. autolyse duration), compensates for
    /// thermal drift during the rest using Newton's cooling law so the dough
    /// arrives at DDT by the end of the rest period, not just at the start.
    ///
    /// Uses the 2-factor method for autolyse (flour + water only) and the
    /// 3-factor method for mix (flour + water + levain).
    ///
    /// - Parameters:
    ///   - desiredDoughTemp: The recipe's reference/target dough temperature (°C).
    ///   - kitchenTemp: Current kitchen temperature (°C), used for flour and levain.
    ///   - restMinutes: Optional rest duration after mixing. When set, the water
    ///     temp is raised/lowered to compensate for drift toward ambient.
    ///   - includeLevain: Whether levain is present (3-factor). False for autolyse (2-factor).
    /// - Returns: Recommended water temperature in °C, clamped to 2...45.
    static func desiredWaterTemperature(
        desiredDoughTemp: Double,
        kitchenTemp: Double,
        restMinutes: Double = 0,
        includeLevain: Bool = true
    ) -> Double {
        let targetAfterRest: Double
        if restMinutes > 0 {
            let decay = exp(restMinutes / doughThermalTimeConstant)
            targetAfterRest = kitchenTemp + (desiredDoughTemp - kitchenTemp) * decay
        } else {
            targetAfterRest = desiredDoughTemp
        }

        let factors = includeLevain ? 3.0 : 2.0
        let raw = (targetAfterRest * factors) - ((factors - 1.0) * kitchenTemp)
        return min(max(raw, 2.0), 45.0)
    }

    /// Computes the effective duration of a method step, applying temperature
    /// adjustment if the step type is temperature-adjusted.
    ///
    /// When `peakProfile` has at least `StarterPeakProfile.minimumSamples`
    /// observations for the kitchen temp bracket at the standard levain ratio,
    /// the observed average replaces the generic levain estimate.
    static func effectiveDuration(
        for step: MethodStep,
        kitchenTemp: Double,
        peakProfile: StarterPeakProfile? = nil
    ) -> Double {
        let stepType = step.stepType

        guard stepType.isTemperatureAdjusted, let refTemp = stepType.referenceTemperatureCelsius else {
            return step.effectiveDuration
        }

        // Levain: prefer user's observed peak time, then recipe override
        // (adjusted via exponential model), then the generic stepped estimate.
        if step.stepTypeID == .buildLevain {
            if let profile = peakProfile,
               let observed = profile.averageMinutes(
                   ratio: levainBuildRatio,
                   tempBracket: TemperatureBracket.bracket(celsius: kitchenTemp)
               )
            {
                return observed
            }
            if step.durationOverrideMinutes != nil {
                return adjustedDuration(
                    baseDurationMinutes: step.effectiveDuration,
                    referenceTemp: refTemp,
                    actualTemp: kitchenTemp
                )
            }
            return levainBuildMinutes(kitchenTemp: kitchenTemp)
        }

        return adjustedDuration(
            baseDurationMinutes: step.effectiveDuration,
            referenceTemp: refTemp,
            actualTemp: kitchenTemp
        )
    }
}
