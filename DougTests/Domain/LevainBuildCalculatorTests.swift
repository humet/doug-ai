#if canImport(DougDomain)
@testable import DougDomain
#else
@testable import Doug
#endif
import Testing

struct LevainBuildCalculatorTests {
    // MARK: - Amount Calculation

    @Test func standardCountryLoaf100gAt1to5to5() {
        let result = LevainBuildCalculator.calculate(.init(
            levainGramsNeeded: 100,
            baseRatio: (1, 5, 5),
            kitchenTemp: 24
        ))
        let total = result.starterGrams + result.flourGrams + result.waterGrams
        #expect(total >= 100)
        #expect(result.totalGrams == total)
        #expect(result.ratio == (1, 5, 5))
        // At 1:5:5 with 25% buffer: 125g total, 11 parts
        // starterGrams ≈ 11, flourGrams ≈ 57, waterGrams ≈ 57
        #expect(result.starterGrams >= 10 && result.starterGrams <= 13)
        #expect(result.flourGrams >= 55 && result.flourGrams <= 60)
    }

    @Test func sameDayCountry100gAt1to2to2() {
        let result = LevainBuildCalculator.calculate(.init(
            levainGramsNeeded: 100,
            baseRatio: (1, 2, 2),
            kitchenTemp: 24
        ))
        #expect(result.totalGrams >= 100)
        #expect(result.ratio == (1, 2, 2))
        // At 1:2:2 with 25% buffer: 125g total, 5 parts
        // starterGrams = 25, flourGrams = 50, waterGrams = 50
        #expect(result.starterGrams == 25)
        #expect(result.flourGrams == 50)
        #expect(result.waterGrams == 50)
    }

    @Test func wholeWheatHoney125g() {
        let result = LevainBuildCalculator.calculate(.init(
            levainGramsNeeded: 125,
            baseRatio: (1, 5, 5),
            kitchenTemp: 24
        ))
        #expect(result.totalGrams >= 125)
    }

    @Test func pizzaDough90gAt1to2to2() {
        let result = LevainBuildCalculator.calculate(.init(
            levainGramsNeeded: 90,
            baseRatio: (1, 2, 2),
            kitchenTemp: 24
        ))
        #expect(result.totalGrams >= 90)
        #expect(result.ratio == (1, 2, 2))
    }

    @Test func zeroBufferProducesExactAmount() {
        let result = LevainBuildCalculator.calculate(.init(
            levainGramsNeeded: 100,
            baseRatio: (1, 5, 5),
            kitchenTemp: 24,
            bufferFraction: 0
        ))
        // With rounding, total may differ slightly from 100
        #expect(abs(result.totalGrams - 100) <= 3)
    }

    @Test func allRecipesProduceEnoughLevain() {
        for recipe in RecipeBook.all {
            let result = LevainBuildCalculator.calculate(.init(
                levainGramsNeeded: recipe.ingredients.levainGrams,
                baseRatio: recipe.levainBuildRatio,
                referenceTemp: recipe.referenceTemperatureCelsius,
                kitchenTemp: 22
            ))
            #expect(
                result.totalGrams >= recipe.ingredients.levainGrams,
                "Recipe \(recipe.name) needs \(recipe.ingredients.levainGrams)g but calculator produces \(result.totalGrams)g"
            )
        }
    }

    @Test func estimatedPeakHoursReflectsTemperature() {
        let warm = LevainBuildCalculator.calculate(.init(
            levainGramsNeeded: 100, baseRatio: (1, 5, 5), kitchenTemp: 28
        ))
        let cool = LevainBuildCalculator.calculate(.init(
            levainGramsNeeded: 100, baseRatio: (1, 5, 5), kitchenTemp: 18
        ))
        #expect(warm.estimatedPeakHours < cool.estimatedPeakHours)
    }

    // MARK: - Temperature-Adjusted Ratios

    @Test func ratioUnchangedAtReferenceTemp() {
        let ratio = LevainBuildCalculator.adjustedRatio(
            base: (1, 5, 5), referenceTemp: 24, kitchenTemp: 24
        )
        #expect(ratio == (1, 5, 5))
    }

    @Test func warmKitchenBumpsRatioUp() {
        let ratio = LevainBuildCalculator.adjustedRatio(
            base: (1, 5, 5), referenceTemp: 24, kitchenTemp: 28
        )
        #expect(ratio.flour == 6)
        #expect(ratio.water == 6)
    }

    @Test func hotKitchenBumpsRatioSignificantly() {
        let ratio = LevainBuildCalculator.adjustedRatio(
            base: (1, 5, 5), referenceTemp: 24, kitchenTemp: 32
        )
        #expect(ratio.flour == 7)
        #expect(ratio.water == 7)
    }

    @Test func coolKitchenDropsRatio() {
        let ratio = LevainBuildCalculator.adjustedRatio(
            base: (1, 5, 5), referenceTemp: 24, kitchenTemp: 20
        )
        #expect(ratio.flour == 4)
        #expect(ratio.water == 4)
    }

    @Test func coldKitchenDropsRatioMore() {
        let ratio = LevainBuildCalculator.adjustedRatio(
            base: (1, 5, 5), referenceTemp: 24, kitchenTemp: 16
        )
        #expect(ratio.flour == 3)
        #expect(ratio.water == 3)
    }

    @Test func sameDayWarmKitchenBumpsUp() {
        let ratio = LevainBuildCalculator.adjustedRatio(
            base: (1, 2, 2), referenceTemp: 24, kitchenTemp: 28
        )
        #expect(ratio.flour == 3)
        #expect(ratio.water == 3)
    }

    @Test func sameDayColdKitchenFloorsAtBase() {
        let ratio = LevainBuildCalculator.adjustedRatio(
            base: (1, 2, 2), referenceTemp: 24, kitchenTemp: 16
        )
        // Can't go below base ratio
        #expect(ratio.flour >= 2)
        #expect(ratio.water >= 2)
    }

    @Test func ratioClampsAtTen() {
        let ratio = LevainBuildCalculator.adjustedRatio(
            base: (1, 8, 8), referenceTemp: 24, kitchenTemp: 40
        )
        #expect(ratio.flour <= 10)
        #expect(ratio.water <= 10)
    }
}
