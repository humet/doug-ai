#if canImport(DougDomain)
@testable import DougDomain
#else
@testable import Doug
#endif
import Testing

struct HydrationCalculatorTests {
    @Test func trueHydrationWith100PercentLevain() {
        // 500g flour, 350g water, 100g levain at 100% hydration
        // Levain contributes 50g flour + 50g water
        // Total flour: 550, total water: 400
        // True hydration: 400/550 = 72.7%
        let hydration = HydrationCalculator.trueHydration(
            flourGrams: 500,
            waterGrams: 350,
            levainGrams: 100,
            levainHydrationPercent: 100
        )
        #expect(abs(hydration - 72.7) < 0.1)
    }

    @Test func doughHydrationIgnoresLevain() {
        let hydration = HydrationCalculator.doughHydration(flourGrams: 500, waterGrams: 350)
        #expect(abs(hydration - 70.0) < 0.01)
    }

    @Test func bakersPercentagesAreCorrect() {
        let bp = HydrationCalculator.bakersPercentages(
            flourGrams: 500,
            waterGrams: 350,
            levainGrams: 100,
            saltGrams: 10
        )
        #expect(bp.flour == 100)
        #expect(abs(bp.water - 70.0) < 0.01)
        #expect(abs(bp.levain - 20.0) < 0.01)
        #expect(abs(bp.salt - 2.0) < 0.01)
    }

    @Test func zeroFlourAndLevainReturnsZero() {
        let hydration = HydrationCalculator.trueHydration(
            flourGrams: 0,
            waterGrams: 350,
            levainGrams: 0,
            levainHydrationPercent: 100
        )
        #expect(hydration == 0)
    }

    @Test func zeroFlourWithLevainStillCalculates() {
        // Levain contributes 50g flour + 50g water
        // Total flour: 50, total water: 400
        let hydration = HydrationCalculator.trueHydration(
            flourGrams: 0,
            waterGrams: 350,
            levainGrams: 100,
            levainHydrationPercent: 100
        )
        #expect(hydration > 0)
    }
}
