@testable import Doug
import Foundation
import SwiftData
import Testing

@Suite(.serialized)
@MainActor
struct ScheduleViewModelYieldTests {
    // MARK: - Helpers

    /// Caller MUST keep the container in scope — if it deallocates, its
    /// `mainContext` dangles and inserts trap.
    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: Schedule.self, ScheduleStep.self, DoughTemperatureReading.self,
            BakeFermentationProfile.self, StarterProfile.self, StarterFeedLog.self,
            configurations: config
        )
    }

    /// An active pizza schedule with its full top-level method as steps, the
    /// first step active — what `startBake` persists, built by hand because
    /// `startBake`'s async notification/Live Activity side effects outlive an
    /// in-memory test container.
    private func makeActivePizzaSchedule(
        in ctx: ModelContext,
        yieldScaleFactor: Double = 1.0,
        yieldCount: Int? = nil,
        yieldUnitGrams: Double? = nil
    ) -> Schedule {
        let schedule = Schedule(
            recipeID: .pizzaDough,
            targetBreadReadyTime: Date().addingTimeInterval(48 * 3600),
            kitchenTemperatureCelsius: 22
        )
        schedule.scheduleStatus = .active
        schedule.yieldScaleFactor = yieldScaleFactor
        schedule.yieldCount = yieldCount
        schedule.yieldUnitGrams = yieldUnitGrams
        ctx.insert(schedule)

        var start = Date()
        for (index, method) in RecipeBook.pizzaDough.method.enumerated() {
            let duration = method.effectiveDuration
            let step = ScheduleStep(
                stepTypeID: method.stepTypeID,
                sequenceIndex: index,
                computedStartTime: start,
                computedEndTime: start.addingTimeInterval(duration * 60),
                computedDurationMinutes: duration
            )
            step.stepStatus = index == 0 ? .active : .upcoming
            step.schedule = schedule
            ctx.insert(step)
            start = step.computedEndTime
        }
        return schedule
    }

    // MARK: - Yield factor on the ViewModel

    @Test func yieldScaleFactorFromCountAndPreset() {
        let vm = ScheduleViewModel()
        vm.selectedRecipeID = .pizzaDough
        vm.yieldCount = 4
        vm.yieldUnitGrams = 270

        let expected = 4.0 * 270.0 / RecipeScaler.totalMass(RecipeBook.pizzaDough.ingredients)
        #expect(abs(vm.yieldScaleFactor - expected) < 0.0001)
    }

    @Test func yieldScaleFactorIsOneWithNoSelection() {
        let vm = ScheduleViewModel()
        vm.selectedRecipeID = .pizzaDough
        #expect(vm.yieldScaleFactor == 1.0)
    }

    @Test func switchingRecipeResetsYieldSelection() {
        let vm = ScheduleViewModel()
        vm.selectedRecipeID = .pizzaDough
        vm.yieldCount = 6
        vm.yieldUnitGrams = 340

        vm.selectedRecipeID = .countryLoaf

        #expect(vm.yieldCount == nil)
        #expect(vm.yieldUnitGrams == nil)
        #expect(vm.yieldScaleFactor == 1.0)
    }

    // MARK: - Schedule scaled accessors

    @Test func scheduleScalesIngredientsAndSummarisesYield() throws {
        let container = try makeContainer()
        let factor = 4.0 * 270.0 / RecipeScaler.totalMass(RecipeBook.pizzaDough.ingredients)
        let schedule = makeActivePizzaSchedule(
            in: container.mainContext,
            yieldScaleFactor: factor, yieldCount: 4, yieldUnitGrams: 270
        )

        let base = RecipeBook.pizzaDough.ingredients
        #expect(abs(schedule.scaledIngredients.flourGrams - base.flourGrams * factor) < 0.0001)
        #expect(abs(schedule.scaledIngredients.levainGrams - base.levainGrams * factor) < 0.0001)
        #expect(schedule.scaledIngredients.extras.count == base.extras.count)
        #expect(schedule.yieldSummary == "4 × 12\" balls (~270g each)")
    }

    @Test func scheduleAtBaseYieldIsUnscaledWithNoSummary() throws {
        let container = try makeContainer()
        let schedule = makeActivePizzaSchedule(in: container.mainContext)

        #expect(schedule.scaledIngredients.flourGrams == RecipeBook.pizzaDough.ingredients.flourGrams)
        #expect(schedule.yieldSummary == nil)
    }

    // MARK: - Levain build seeds from scaled ingredients

    @Test func feedDefaultsSeedFromScaledLevain() throws {
        let container = try makeContainer()
        let factor = 2.0
        let schedule = makeActivePizzaSchedule(in: container.mainContext, yieldScaleFactor: factor)
        let buildStep = try #require(schedule.steps.first {
            $0.stepTypeID == StepTypeID.buildLevain.rawValue
        })

        let vm = ScheduleViewModel()
        vm.activeSchedule = schedule
        vm.resetFeedState()
        vm.initializeFeedDefaults(for: buildStep)

        let expected = LevainBuildCalculator.calculate(.init(
            levainGramsNeeded: RecipeBook.pizzaDough.ingredients.levainGrams * factor,
            baseRatio: schedule.recipe.levainBuildRatio,
            referenceTemp: schedule.recipe.referenceTemperatureCelsius,
            kitchenTemp: schedule.kitchenTemperatureCelsius
        ))
        #expect(vm.feedStarterGrams == String(Int(expected.starterGrams)))
    }

    // MARK: - Pizza bake step flow

    @Test func pizzaBakeFlowsRetardThenTemperThenFinishable() throws {
        let container = try makeContainer()
        // A plain context (autosave off) — markStepDone's side-effect fetches
        // mid-mutation reset autosaving mainContext models out from under us.
        let ctx = ModelContext(container)
        let schedule = makeActivePizzaSchedule(in: ctx)

        let vm = ScheduleViewModel()
        vm.activeSchedule = schedule

        let topLevel = schedule.steps
            .filter { $0.parentStep == nil }
            .sorted { $0.sequenceIndex < $1.sequenceIndex }
        #expect(topLevel.last?.stepTypeID == StepTypeID.temper.rawValue)
        let retard = try #require(topLevel.first { $0.stepTypeID == StepTypeID.coldRetardBalls.rawValue })
        let temper = try #require(topLevel.first { $0.stepTypeID == StepTypeID.temper.rawValue })

        // Walk every step before the temper to done, as a bake would.
        for step in topLevel where step !== temper {
            vm.markStepDone(step, modelContext: ctx)
        }
        #expect(retard.stepStatus == .done)
        #expect(temper.stepStatus == .active, "Completing the retard should promote the temper")

        vm.markStepDone(temper, modelContext: ctx)
        #expect(temper.stepStatus == .done)
        let unfinished = topLevel.filter { $0.stepStatus != .done && $0.stepStatus != .skipped }
        #expect(unfinished.isEmpty, "All steps done — the bake is finishable")
    }
}
