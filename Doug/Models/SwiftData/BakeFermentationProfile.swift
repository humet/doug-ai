import Foundation
import SwiftData

/// The record of a finished bake — fermentation telemetry captured from the
/// schedule plus the baker's reflection (rating, structured tags, notes, photos).
/// Linked from `Schedule.fermentationProfile`; surfaced in the History tab.
@Model
final class BakeFermentationProfile {
    var recipeID: String
    /// Snapshot of the recipe name at completion, for cheap list rendering.
    var recipeName: String = ""
    var initialMixTemp: Double
    var finalDegreeHours: Double
    var targetDegreeHoursUsed: Double
    var kitchenTemperatureCelsius: Double
    var outcomeNote: String?

    /// Reflection scores, 1–5. `0` means unrated.
    var rating: Int = 0
    var crumbOpenness: Int = 0
    var crustColor: Int = 0
    var sourness: Int = 0
    var ovenSpring: Int = 0

    var completedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \BakePhoto.profile)
    var photos: [BakePhoto] = []

    init(
        recipeID: RecipeID,
        recipeName: String = "",
        initialMixTemp: Double,
        finalDegreeHours: Double,
        targetDegreeHoursUsed: Double,
        kitchenTemperatureCelsius: Double,
        outcomeNote: String? = nil,
        rating: Int = 0,
        crumbOpenness: Int = 0,
        crustColor: Int = 0,
        sourness: Int = 0,
        ovenSpring: Int = 0
    ) {
        self.recipeID = recipeID.rawValue
        self.recipeName = recipeName
        self.initialMixTemp = initialMixTemp
        self.finalDegreeHours = finalDegreeHours
        self.targetDegreeHoursUsed = targetDegreeHoursUsed
        self.kitchenTemperatureCelsius = kitchenTemperatureCelsius
        self.outcomeNote = outcomeNote
        self.rating = rating
        self.crumbOpenness = crumbOpenness
        self.crustColor = crustColor
        self.sourness = sourness
        self.ovenSpring = ovenSpring
        completedAt = Date()
    }

    /// Photos in display order.
    var orderedPhotos: [BakePhoto] {
        photos.sorted { $0.order < $1.order }
    }
}
