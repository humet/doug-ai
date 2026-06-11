@testable import Doug
import Foundation
import SwiftData
import Testing

@MainActor
@Suite(.serialized)
struct ScheduleViewModelFinishBakeTests {
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

    /// An active schedule with two readings an hour apart at 24°C → 20 degree-hours.
    private func makeActiveSchedule(in ctx: ModelContext) -> Schedule {
        let schedule = Schedule(
            recipeID: RecipeBook.countryLoaf.id,
            targetBreadReadyTime: Date(),
            kitchenTemperatureCelsius: 22
        )
        schedule.scheduleStatus = .active
        ctx.insert(schedule)

        let start = Date(timeIntervalSince1970: 1_000_000)
        let r1 = DoughTemperatureReading(
            timestamp: start, temperatureCelsius: 24, sequenceNumber: 0, accumulatedDegreeHours: 0
        )
        let r2 = DoughTemperatureReading(
            timestamp: start.addingTimeInterval(3600), temperatureCelsius: 24,
            sequenceNumber: 1, accumulatedDegreeHours: 20
        )
        r1.schedule = schedule
        r2.schedule = schedule
        ctx.insert(r1)
        ctx.insert(r2)
        return schedule
    }

    @Test func finishWithReflectionCreatesLinkedProfileAndPhotos() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let schedule = makeActiveSchedule(in: ctx)
        let viewModel = ScheduleViewModel()
        viewModel.activeSchedule = schedule

        let reflection = BakeReflection(
            rating: 4, crumbOpenness: 3, crustColor: 5, sourness: 2, ovenSpring: 4,
            notes: "  Lovely oven spring  ",
            photoData: [Data([0x1, 0x2]), Data([0x3])]
        )
        viewModel.finishBake(reflection: reflection, modelContext: ctx)

        #expect(viewModel.activeSchedule == nil)
        #expect(schedule.scheduleStatus == .complete)
        #expect(schedule.completedAt != nil)

        let profile = try #require(schedule.fermentationProfile)
        #expect(profile.rating == 4)
        #expect(profile.crumbOpenness == 3)
        #expect(profile.ovenSpring == 4)
        #expect(profile.outcomeNote == "Lovely oven spring") // trimmed
        #expect(profile.recipeName == RecipeBook.countryLoaf.name)
        #expect(profile.photos.count == 2)
        #expect(abs(profile.finalDegreeHours - 20) < 0.001)
        #expect(profile.targetDegreeHoursUsed == RecipeBook.countryLoaf.degreeHourTarget)

        let profiles = try ctx.fetch(FetchDescriptor<BakeFermentationProfile>())
        #expect(profiles.count == 1)
    }

    @Test func finishWithoutReflectionCompletesWithoutProfile() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let schedule = makeActiveSchedule(in: ctx)
        let viewModel = ScheduleViewModel()
        viewModel.activeSchedule = schedule

        viewModel.finishBake(reflection: nil, modelContext: ctx)

        #expect(viewModel.activeSchedule == nil)
        #expect(schedule.scheduleStatus == .complete)
        #expect(schedule.completedAt != nil)
        #expect(schedule.fermentationProfile == nil)

        let profiles = try ctx.fetch(FetchDescriptor<BakeFermentationProfile>())
        #expect(profiles.isEmpty)
    }

    @Test func blankNotesBecomeNil() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let schedule = makeActiveSchedule(in: ctx)
        let viewModel = ScheduleViewModel()
        viewModel.activeSchedule = schedule

        viewModel.finishBake(reflection: BakeReflection(notes: "   "), modelContext: ctx)

        #expect(schedule.fermentationProfile?.outcomeNote == nil)
    }

    @Test func recordsCalibratedTargetWhenSet() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let schedule = makeActiveSchedule(in: ctx)
        schedule.calibratedDegreeHourTarget = 92.5

        let viewModel = ScheduleViewModel()
        viewModel.activeSchedule = schedule
        viewModel.finishBake(reflection: BakeReflection(notes: ""), modelContext: ctx)

        #expect(schedule.fermentationProfile?.targetDegreeHoursUsed == 92.5)
    }

    @Test func finalDegreeHoursExtrapolateToBulkEnd() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let schedule = makeActiveSchedule(in: ctx)

        // Bulk ended an hour after the last 24°C reading: the recorded total
        // must include the unlogged tail, not freeze at the last reading.
        let lastReading = Date(timeIntervalSince1970: 1_000_000).addingTimeInterval(3600)
        let bulk = ScheduleStep(
            stepTypeID: .bulkFerment,
            sequenceIndex: 0,
            computedStartTime: Date(timeIntervalSince1970: 1_000_000),
            computedEndTime: lastReading.addingTimeInterval(3600),
            computedDurationMinutes: 120
        )
        bulk.stepStatus = .done
        bulk.actualEndTime = lastReading.addingTimeInterval(3600)
        bulk.schedule = schedule
        ctx.insert(bulk)

        let viewModel = ScheduleViewModel()
        viewModel.activeSchedule = schedule
        viewModel.finishBake(reflection: BakeReflection(notes: ""), modelContext: ctx)

        let profile = try #require(schedule.fermentationProfile)
        // 20 integrated + (24 - 4) × 1h tail = 40.
        #expect(abs(profile.finalDegreeHours - 40) < 0.001)
    }

    @Test func finishAndCancelResetBulkTargetFlag() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let finished = makeActiveSchedule(in: ctx)
        let finishViewModel = ScheduleViewModel()
        finishViewModel.activeSchedule = finished
        finishViewModel.bulkFermentTargetReached = true
        finishViewModel.finishBake(reflection: nil, modelContext: ctx)
        #expect(!finishViewModel.bulkFermentTargetReached)

        let cancelled = makeActiveSchedule(in: ctx)
        let cancelViewModel = ScheduleViewModel()
        cancelViewModel.activeSchedule = cancelled
        cancelViewModel.bulkFermentTargetReached = true
        cancelViewModel.cancelBake(modelContext: ctx)
        #expect(!cancelViewModel.bulkFermentTargetReached)
    }
}
