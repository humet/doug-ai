import Foundation

/// Pure fermentation summary for a finished bake. Derived from the schedule's
/// temperature readings so the History record can show how the bake actually went.
struct BakeFermentationSummary: Equatable {
    let finalDegreeHours: Double
    let targetDegreeHoursUsed: Double
    let initialMixTemp: Double
    let kitchenTemperatureCelsius: Double
}

/// Builds a `BakeFermentationSummary` from a recipe and the dough temperature
/// readings logged during the bake. Kept pure (no SwiftData) so it's testable
/// without a simulator; the ViewModel turns the summary into a persisted
/// `BakeFermentationProfile`.
enum BakeRecordBuilder {
    static func summarize(
        recipe: Recipe,
        kitchenTempCelsius: Double,
        readings: [(timestamp: Date, temperatureCelsius: Double)]
    ) -> BakeFermentationSummary {
        let finalDegreeHours = DegreeHourCalculator.accumulatedDegreeHours(readings: readings)
        // Initial mix temp is the earliest reading; fall back to kitchen temp when
        // no readings were logged (e.g. a bake finished without fold check-ins).
        let initialMixTemp = readings
            .min { $0.timestamp < $1.timestamp }?
            .temperatureCelsius ?? kitchenTempCelsius

        return BakeFermentationSummary(
            finalDegreeHours: finalDegreeHours,
            targetDegreeHoursUsed: recipe.degreeHourTarget,
            initialMixTemp: initialMixTemp,
            kitchenTemperatureCelsius: kitchenTempCelsius
        )
    }
}
