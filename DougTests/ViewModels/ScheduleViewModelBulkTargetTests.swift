@testable import Doug
import Foundation
import SwiftData
import Testing

@MainActor
@Suite(.serialized)
struct ScheduleViewModelBulkTargetTests {
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

    /// An active schedule with a bulk ferment step and a single 24°C reading
    /// taken at `readingAge` before `now`. Country loaf targets 80 degree-hours;
    /// at 24°C the dough accumulates 20 degree-hours per hour, so the target is
    /// four hours of extrapolation away from the reading.
    private func makeSchedule(
        in ctx: ModelContext,
        bulkStatus: StepStatus,
        readingAge: TimeInterval,
        now: Date
    ) -> Schedule {
        let schedule = Schedule(
            recipeID: RecipeBook.countryLoaf.id,
            targetBreadReadyTime: now.addingTimeInterval(6 * 3600),
            kitchenTemperatureCelsius: 22
        )
        schedule.scheduleStatus = .active
        ctx.insert(schedule)

        let bulk = ScheduleStep(
            stepTypeID: .bulkFerment,
            sequenceIndex: 0,
            computedStartTime: now.addingTimeInterval(-readingAge),
            computedEndTime: now.addingTimeInterval(3600),
            computedDurationMinutes: (readingAge + 3600) / 60
        )
        bulk.stepStatus = bulkStatus
        bulk.schedule = schedule
        ctx.insert(bulk)

        let reading = DoughTemperatureReading(
            timestamp: now.addingTimeInterval(-readingAge),
            temperatureCelsius: 24,
            sequenceNumber: 0,
            accumulatedDegreeHours: 0
        )
        reading.schedule = schedule
        ctx.insert(reading)
        return schedule
    }

    @Test func tickSetsTargetReachedWhenExtrapolationNearsTarget() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let now = Date()
        // Reading four hours ago: extrapolation reaches the full 80 degree-hours.
        let schedule = makeSchedule(in: ctx, bulkStatus: .active, readingAge: 4 * 3600, now: now)
        let viewModel = ScheduleViewModel()
        viewModel.activeSchedule = schedule

        viewModel.refreshBulkFermentTarget(now: now)

        #expect(viewModel.bulkFermentTargetReached)
    }

    @Test func tickDoesNotSetFlagFarFromTarget() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let now = Date()
        // Reading one hour ago: 20 of 80 degree-hours — three hours short.
        let schedule = makeSchedule(in: ctx, bulkStatus: .active, readingAge: 3600, now: now)
        let viewModel = ScheduleViewModel()
        viewModel.activeSchedule = schedule

        viewModel.refreshBulkFermentTarget(now: now)

        #expect(!viewModel.bulkFermentTargetReached)
    }

    @Test(arguments: [StepStatus.upcoming, StepStatus.done])
    func tickIgnoresWhenBulkNotActive(status: StepStatus) throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let now = Date()
        // Past target on extrapolation, but bulk isn't the active step.
        let schedule = makeSchedule(in: ctx, bulkStatus: status, readingAge: 5 * 3600, now: now)
        let viewModel = ScheduleViewModel()
        viewModel.activeSchedule = schedule

        viewModel.refreshBulkFermentTarget(now: now)

        #expect(!viewModel.bulkFermentTargetReached)
    }

    @Test func tickDerivesFlagFromScratchAfterRelaunch() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let now = Date()
        let schedule = makeSchedule(in: ctx, bulkStatus: .active, readingAge: 5 * 3600, now: now)

        // A fresh ViewModel (as after app relaunch) starts with the flag unset
        // and must re-derive it from the restored schedule within one tick.
        let viewModel = ScheduleViewModel()
        viewModel.activeSchedule = schedule
        #expect(!viewModel.bulkFermentTargetReached)

        viewModel.refreshBulkFermentTarget(now: now)

        #expect(viewModel.bulkFermentTargetReached)
    }
}
