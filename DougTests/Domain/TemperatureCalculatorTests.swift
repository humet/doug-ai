#if canImport(DougDomain)
@testable import DougDomain
#else
@testable import Doug
#endif
import Testing

struct TemperatureCalculatorTests {
    // MARK: - Exponential Adjustment

    @Test func warmKitchenShortensDuration() {
        // 28°C is 4 degrees above 24°C reference
        let adjusted = TemperatureCalculator.adjustedDuration(
            baseDurationMinutes: 240,
            referenceTemp: 24.0,
            actualTemp: 28.0
        )
        // Should be shorter: 240 × (0.93)^4 ≈ 179
        #expect(adjusted < 240)
        #expect(adjusted > 170 && adjusted < 190)
    }

    @Test func coldKitchenLengthensDuration() {
        // 20°C is 4 degrees below 24°C reference
        let adjusted = TemperatureCalculator.adjustedDuration(
            baseDurationMinutes: 240,
            referenceTemp: 24.0,
            actualTemp: 20.0
        )
        // Should be longer: 240 × (0.93)^(-4) ≈ 320
        #expect(adjusted > 240)
        #expect(adjusted > 300 && adjusted < 340)
    }

    @Test func referenceTemperatureReturnsBaseDuration() {
        let adjusted = TemperatureCalculator.adjustedDuration(
            baseDurationMinutes: 240,
            referenceTemp: 24.0,
            actualTemp: 24.0
        )
        #expect(abs(adjusted - 240) < 0.01)
    }

    // MARK: - Levain Estimates

    @Test func levainBuildWarmKitchen() {
        let minutes = TemperatureCalculator.levainBuildMinutes(kitchenTemp: 28)
        #expect(minutes == 240) // 4 hours
    }

    @Test func levainBuildModerateKitchen() {
        let minutes = TemperatureCalculator.levainBuildMinutes(kitchenTemp: 23)
        #expect(minutes == 300) // 5 hours
    }

    @Test func levainBuildColdKitchen() {
        let minutes = TemperatureCalculator.levainBuildMinutes(kitchenTemp: 18)
        #expect(minutes == 360) // 6 hours
    }

    // MARK: - Effective Duration

    @Test func nonTempAdjustedStepIgnoresKitchenTemp() {
        let step = MethodStep(stepTypeID: .mix)
        let duration = TemperatureCalculator.effectiveDuration(for: step, kitchenTemp: 30)
        #expect(duration == 5) // base duration, unchanged
    }

    @Test func bulkFermentAdjustsForTemperature() {
        let step = MethodStep(stepTypeID: .bulkFerment, durationOverrideMinutes: 240)
        let hot = TemperatureCalculator.effectiveDuration(for: step, kitchenTemp: 28)
        let cold = TemperatureCalculator.effectiveDuration(for: step, kitchenTemp: 20)
        #expect(hot < cold)
        #expect(hot < 240)
        #expect(cold > 240)
    }

    // MARK: - Fridge Warm-Up

    @Test func fridgeWarmUpWarmKitchen() {
        let minutes = TemperatureCalculator.fridgeWarmUpMinutes(kitchenTempCelsius: 28)
        #expect(minutes == 60)
    }

    @Test func fridgeWarmUpModerateKitchen() {
        let minutes = TemperatureCalculator.fridgeWarmUpMinutes(kitchenTempCelsius: 23)
        #expect(minutes == 90)
    }

    @Test func fridgeWarmUpCoolKitchen() {
        let minutes = TemperatureCalculator.fridgeWarmUpMinutes(kitchenTempCelsius: 18)
        #expect(minutes == 120)
    }
}
