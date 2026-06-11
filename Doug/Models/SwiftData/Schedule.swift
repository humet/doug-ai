import Foundation
import SwiftData

@Model
final class Schedule {
    var recipeID: String
    var targetBreadReadyTime: Date
    var kitchenTemperatureCelsius: Double
    var status: String
    var createdAt: Date
    var pausedAt: Date?
    /// Set when the bake is finished; drives History ordering. Nil while active.
    var completedAt: Date?
    /// Personalized degree-hour target resolved once at bake start from past
    /// good bakes (`DegreeHourCalibrator`). Nil until enough history exists;
    /// optional so pre-existing stores migrate without a versioned schema.
    var calibratedDegreeHourTarget: Double?
    /// Multiplier applied to the recipe's ingredient grams for this bake.
    /// Default at the declaration site so pre-existing stores migrate without
    /// a versioned schema.
    var yieldScaleFactor: Double = 1.0
    /// The unit count the user chose (display only — the factor is what
    /// scales). Nil means the recipe's base yield.
    var yieldCount: Int?
    /// Grams per unit when chosen from a size preset (display only).
    var yieldUnitGrams: Double?

    @Relationship(deleteRule: .cascade, inverse: \ScheduleStep.schedule)
    var steps: [ScheduleStep] = []

    @Relationship(deleteRule: .cascade, inverse: \DoughTemperatureReading.schedule)
    var temperatureReadings: [DoughTemperatureReading] = []

    @Relationship(deleteRule: .cascade)
    var fermentationProfile: BakeFermentationProfile?

    init(
        recipeID: RecipeID,
        targetBreadReadyTime: Date,
        kitchenTemperatureCelsius: Double
    ) {
        self.recipeID = recipeID.rawValue
        self.targetBreadReadyTime = targetBreadReadyTime
        self.kitchenTemperatureCelsius = kitchenTemperatureCelsius
        status = ScheduleStatus.planning.rawValue
        createdAt = Date()
    }

    var scheduleStatus: ScheduleStatus {
        get { ScheduleStatus(rawValue: status) ?? .planning }
        set { status = newValue.rawValue }
    }

    var recipe: Recipe {
        RecipeBook.recipe(for: RecipeID(rawValue: recipeID)!)
    }
}

extension Schedule {
    /// The degree-hour target this bake actually runs against: the calibrated
    /// value when one was resolved at bake start, otherwise the recipe default.
    var effectiveDegreeHourTarget: Double {
        calibratedDegreeHourTarget ?? recipe.degreeHourTarget
    }

    /// The recipe's ingredients scaled to this bake's chosen yield.
    var scaledIngredients: Ingredients {
        RecipeScaler.scaled(recipe.ingredients, by: yieldScaleFactor)
    }

    /// "4 × 12″ balls (~270g each)" / "2 loaves" — nil at the recipe's base
    /// yield, where there's nothing worth calling out.
    var yieldSummary: String? {
        guard let count = yieldCount else { return nil }
        let yield = recipe.yield
        if let grams = yieldUnitGrams {
            let preset = yield.sizePresets.first { $0.unitGrams == grams }
            let size = preset.map { "\($0.label) " } ?? ""
            return "\(count) × \(size)\(yield.unitName(for: count)) (~\(Int(grams.rounded()))g each)"
        }
        guard count != yield.baseCount else { return nil }
        return "\(count) \(yield.unitName(for: count))"
    }

    var bulkFermentStep: ScheduleStep? {
        steps.first { $0.parentStep == nil && $0.stepTypeID == StepTypeID.bulkFerment.rawValue }
    }

    /// Cutoff date for degree-hour extrapolation. Temperature readings are only
    /// prompted through the fold window, so fermentation continues past the last
    /// reading: extrapolate to `now` until bulk is finished, then freeze at the
    /// moment bulk actually ended. Bulk being `.upcoming` still returns `now` —
    /// the dough ferments from mix onward regardless of which step is active.
    func degreeHourCutoff(now: Date) -> Date {
        guard let bulk = bulkFermentStep else { return now }
        switch bulk.stepStatus {
        case .done, .skipped:
            return bulk.actualEndTime ?? bulk.computedEndTime
        default:
            return now
        }
    }
}

enum ScheduleStatus: String, Codable {
    case planning
    case active
    case complete
}
