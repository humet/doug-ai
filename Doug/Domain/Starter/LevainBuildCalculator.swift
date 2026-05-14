import Foundation

enum LevainBuildCalculator {
    static let defaultBufferFraction = 0.25

    struct Input {
        let levainGramsNeeded: Double
        let levainHydrationPercent: Double
        let baseRatio: (starter: Int, flour: Int, water: Int)
        let referenceTemp: Double
        let kitchenTemp: Double
        let bufferFraction: Double

        init(
            levainGramsNeeded: Double,
            levainHydrationPercent: Double = 100,
            baseRatio: (starter: Int, flour: Int, water: Int),
            referenceTemp: Double = 24.0,
            kitchenTemp: Double,
            bufferFraction: Double = LevainBuildCalculator.defaultBufferFraction
        ) {
            self.levainGramsNeeded = levainGramsNeeded
            self.levainHydrationPercent = levainHydrationPercent
            self.baseRatio = baseRatio
            self.referenceTemp = referenceTemp
            self.kitchenTemp = kitchenTemp
            self.bufferFraction = bufferFraction
        }
    }

    struct Result {
        let starterGrams: Double
        let flourGrams: Double
        let waterGrams: Double
        let totalGrams: Double
        let ratio: (starter: Int, flour: Int, water: Int)
        let estimatedPeakHours: Double
    }

    // MARK: - Temperature-Adjusted Ratio

    static func adjustedRatio(
        base: (starter: Int, flour: Int, water: Int),
        referenceTemp: Double,
        kitchenTemp: Double
    ) -> (starter: Int, flour: Int, water: Int) {
        let delta = kitchenTemp - referenceTemp
        let steps = Int((delta / 4.0).rounded())

        let adjustedFlour = max(2, min(base.flour + steps, 10))
        let adjustedWater = max(2, min(base.water + steps, 10))

        return (base.starter, adjustedFlour, adjustedWater)
    }

    // MARK: - Amount Calculation

    static func calculate(_ input: Input) -> Result {
        let ratio = adjustedRatio(
            base: input.baseRatio,
            referenceTemp: input.referenceTemp,
            kitchenTemp: input.kitchenTemp
        )

        let totalNeeded = input.levainGramsNeeded * (1 + input.bufferFraction)
        let parts = Double(ratio.starter + ratio.flour + ratio.water)

        let starterGrams = (totalNeeded * Double(ratio.starter) / parts).rounded()
        let flourGrams = (totalNeeded * Double(ratio.flour) / parts).rounded()
        let waterGrams = (totalNeeded * Double(ratio.water) / parts).rounded()

        let estimatedPeakHours = TemperatureCalculator.levainBuildMinutes(
            kitchenTemp: input.kitchenTemp
        ) / 60.0

        return Result(
            starterGrams: starterGrams,
            flourGrams: flourGrams,
            waterGrams: waterGrams,
            totalGrams: starterGrams + flourGrams + waterGrams,
            ratio: ratio,
            estimatedPeakHours: estimatedPeakHours
        )
    }
}
