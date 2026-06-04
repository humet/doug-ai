#if canImport(DougDomain)
@testable import DougDomain
#else
@testable import Doug
#endif
import Foundation
import Testing

struct BakeRecordBuilderTests {
    private let recipe = RecipeBook.countryLoaf

    @Test func usesRecipeDegreeHourTarget() {
        let summary = BakeRecordBuilder.summarize(
            recipe: recipe,
            kitchenTempCelsius: 22,
            readings: []
        )
        #expect(summary.targetDegreeHoursUsed == recipe.degreeHourTarget)
    }

    @Test func initialMixTempFallsBackToKitchenTempWhenNoReadings() {
        let summary = BakeRecordBuilder.summarize(
            recipe: recipe,
            kitchenTempCelsius: 21.5,
            readings: []
        )
        #expect(summary.initialMixTemp == 21.5)
        #expect(summary.finalDegreeHours == 0)
    }

    @Test func initialMixTempIsEarliestReadingRegardlessOfOrder() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let readings = [
            (timestamp: start.addingTimeInterval(7200), temperatureCelsius: 26.0),
            (timestamp: start, temperatureCelsius: 24.0),
            (timestamp: start.addingTimeInterval(3600), temperatureCelsius: 25.0),
        ]
        let summary = BakeRecordBuilder.summarize(
            recipe: recipe,
            kitchenTempCelsius: 20,
            readings: readings
        )
        #expect(summary.initialMixTemp == 24.0)
    }

    @Test func finalDegreeHoursMatchesCalculator() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let readings = [
            (timestamp: start, temperatureCelsius: 24.0),
            (timestamp: start.addingTimeInterval(3600), temperatureCelsius: 24.0),
        ]
        let summary = BakeRecordBuilder.summarize(
            recipe: recipe,
            kitchenTempCelsius: 24,
            readings: readings
        )
        let expected = DegreeHourCalculator.accumulatedDegreeHours(readings: readings)
        #expect(summary.finalDegreeHours == expected)
        // (24 - 4 base) * 1 hour = 20 degree-hours.
        #expect(abs(summary.finalDegreeHours - 20) < 0.001)
    }

    @Test func passesKitchenTempThrough() {
        let summary = BakeRecordBuilder.summarize(
            recipe: recipe,
            kitchenTempCelsius: 23.3,
            readings: []
        )
        #expect(summary.kitchenTemperatureCelsius == 23.3)
    }
}
