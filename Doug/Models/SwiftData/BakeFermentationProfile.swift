import Foundation
import SwiftData

@Model
final class BakeFermentationProfile {
    var recipeID: String
    var initialMixTemp: Double
    var finalDegreeHours: Double
    var targetDegreeHoursUsed: Double
    var kitchenTemperatureCelsius: Double
    var outcomeNote: String?
    var completedAt: Date

    init(
        recipeID: RecipeID,
        initialMixTemp: Double,
        finalDegreeHours: Double,
        targetDegreeHoursUsed: Double,
        kitchenTemperatureCelsius: Double,
        outcomeNote: String? = nil
    ) {
        self.recipeID = recipeID.rawValue
        self.initialMixTemp = initialMixTemp
        self.finalDegreeHours = finalDegreeHours
        self.targetDegreeHoursUsed = targetDegreeHoursUsed
        self.kitchenTemperatureCelsius = kitchenTemperatureCelsius
        self.outcomeNote = outcomeNote
        self.completedAt = Date()
    }
}
