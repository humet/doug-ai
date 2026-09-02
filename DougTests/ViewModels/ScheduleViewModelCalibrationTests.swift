@testable import Doug
import Foundation
import SwiftData
import Testing

@MainActor
@Suite(.serialized)
struct ScheduleViewModelCalibrationTests {
    /// Caller MUST keep the container in scope — if it deallocates, its
    /// `mainContext` dangles and inserts trap.
    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: Schedule.self, ScheduleStep.self, DoughTemperatureReading.self,
            BakeFermentationProfile.self, BakePhoto.self,
            configurations: config
        )
    }

    private func makeSchedule(in ctx: ModelContext) -> Schedule {
        let schedule = Schedule(
            recipeID: RecipeBook.countryLoaf.id,
            targetBreadReadyTime: Date().addingTimeInterval(24 * 3600),
            kitchenTemperatureCelsius: 22
        )
        ctx.insert(schedule)
        return schedule
    }

    private func insertGoodProfile(
        in ctx: ModelContext,
        finalDegreeHours: Double,
        daysAgo: Double
    ) {
        let profile = BakeFermentationProfile(
            recipeID: RecipeBook.countryLoaf.id,
            recipeName: RecipeBook.countryLoaf.name,
            initialMixTemp: 24,
            finalDegreeHours: finalDegreeHours,
            targetDegreeHoursUsed: RecipeBook.countryLoaf.degreeHourTarget,
            kitchenTemperatureCelsius: 22,
            rating: 5
        )
        profile.completedAt = Date().addingTimeInterval(-daysAgo * 86400)
        ctx.insert(profile)
    }

    @Test func calibratesFromThreeGoodBakes() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        for daysAgo in [3.0, 2.0, 1.0] {
            insertGoodProfile(in: ctx, finalDegreeHours: 90, daysAgo: daysAgo)
        }
        let schedule = makeSchedule(in: ctx)

        let viewModel = ScheduleViewModel()
        viewModel.calibrateDegreeHourTarget(for: schedule, modelContext: ctx)

        let calibrated = try #require(schedule.calibratedDegreeHourTarget)
        #expect(abs(calibrated - 90) < 0.001)
        #expect(abs(schedule.effectiveDegreeHourTarget - 90) < 0.001)
    }

    @Test func fallsBackToRecipeDefaultWithoutEnoughHistory() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        insertGoodProfile(in: ctx, finalDegreeHours: 90, daysAgo: 1)
        let schedule = makeSchedule(in: ctx)

        let viewModel = ScheduleViewModel()
        viewModel.calibrateDegreeHourTarget(for: schedule, modelContext: ctx)

        #expect(schedule.calibratedDegreeHourTarget == nil)
        #expect(schedule.effectiveDegreeHourTarget == RecipeBook.countryLoaf.degreeHourTarget)
    }
}
