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

    @Relationship(deleteRule: .cascade, inverse: \ScheduleStep.schedule)
    var steps: [ScheduleStep] = []

    @Relationship(deleteRule: .cascade, inverse: \DoughTemperatureReading.schedule)
    var temperatureReadings: [DoughTemperatureReading] = []

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

enum ScheduleStatus: String, Codable {
    case planning
    case active
    case complete
}
