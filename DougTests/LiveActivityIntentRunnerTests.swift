@testable import Doug
import Foundation
import SwiftData
import Testing

@MainActor
struct LiveActivityIntentRunnerTests {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            Schedule.self,
            ScheduleStep.self,
            DoughTemperatureReading.self,
            BakeFermentationProfile.self,
            StarterFeedLog.self,
            StarterProfile.self,
            RevivalPlan.self,
            RevivalFeedStep.self,
            UserAvailability.self,
            UnavailableWindow.self,
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    /// Active bake step with the covered phase running.
    private func makeBakeSchedule(
        anchor: Date,
        context: ModelContext
    ) -> (schedule: Schedule, phases: [ScheduleStep]) {
        let schedule = Schedule(
            recipeID: .countryLoaf,
            targetBreadReadyTime: anchor.addingTimeInterval(60 * 60),
            kitchenTemperatureCelsius: 22
        )
        schedule.scheduleStatus = .active
        context.insert(schedule)

        let bake = ScheduleStep(
            stepTypeID: .bake,
            sequenceIndex: 0,
            computedStartTime: anchor,
            computedEndTime: anchor.addingTimeInterval(45 * 60),
            computedDurationMinutes: 45
        )
        bake.schedule = schedule
        bake.stepStatus = .active
        context.insert(bake)

        let covered = ScheduleStep(
            stepTypeID: .bakeCovered,
            sequenceIndex: 0,
            computedStartTime: anchor,
            computedEndTime: anchor.addingTimeInterval(20 * 60),
            computedDurationMinutes: 20
        )
        covered.parentStep = bake
        covered.schedule = schedule
        covered.stepStatus = .active
        context.insert(covered)

        let uncovered = ScheduleStep(
            stepTypeID: .bakeUncovered,
            sequenceIndex: 1,
            computedStartTime: anchor.addingTimeInterval(20 * 60),
            computedEndTime: anchor.addingTimeInterval(45 * 60),
            computedDurationMinutes: 25
        )
        uncovered.parentStep = bake
        uncovered.schedule = schedule
        context.insert(uncovered)

        return (schedule, [covered, uncovered])
    }

    @Test func backgroundLaunchCompletesPhaseDirectly() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let anchor = Date().addingTimeInterval(-21 * 60)
        let (_, phases) = makeBakeSchedule(anchor: anchor, context: context)

        // Fresh router with no registered view model — the cold-launch path.
        LiveActivityIntentRunner.completeBakePhase(
            stepTypeID: phases[0].stepTypeID,
            sequenceIndex: phases[0].sequenceIndex,
            router: NotificationRouter(),
            modelContext: context
        )

        #expect(phases[0].stepStatus == .done)
        // The handoff applies here too: uncovered promotes immediately.
        #expect(phases[1].stepStatus == .active)
    }

    @Test func backgroundLaunchLastPhaseCompletesBakeStep() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let anchor = Date().addingTimeInterval(-40 * 60)
        let (schedule, phases) = makeBakeSchedule(anchor: anchor, context: context)
        phases[0].stepStatus = .done
        phases[0].actualEndTime = phases[0].computedEndTime
        phases[1].stepStatus = .active

        LiveActivityIntentRunner.completeBakePhase(
            stepTypeID: phases[1].stepTypeID,
            sequenceIndex: phases[1].sequenceIndex,
            router: NotificationRouter(),
            modelContext: context
        )

        #expect(phases[1].stepStatus == .done)
        let bake = schedule.steps.first { $0.stepTypeID == StepTypeID.bake.rawValue }
        #expect(bake?.stepStatus == .done)
    }

    @Test func completedPhaseIsNotRedone() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let anchor = Date().addingTimeInterval(-21 * 60)
        let (_, phases) = makeBakeSchedule(anchor: anchor, context: context)
        phases[0].stepStatus = .done
        let originalEnd = phases[0].actualEndTime

        LiveActivityIntentRunner.completeBakePhase(
            stepTypeID: phases[0].stepTypeID,
            sequenceIndex: phases[0].sequenceIndex,
            router: NotificationRouter(),
            modelContext: context
        )

        // A stale double-tap must not re-complete or shift anything.
        #expect(phases[0].actualEndTime == originalEnd)
        #expect(phases[1].stepStatus == .upcoming)
    }

    @Test func routesThroughRegisteredViewModel() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let anchor = Date().addingTimeInterval(-21 * 60)
        let (schedule, phases) = makeBakeSchedule(anchor: anchor, context: context)

        let router = NotificationRouter()
        let viewModel = ScheduleViewModel()
        viewModel.activeSchedule = schedule
        router.registerScheduleViewModel(viewModel)

        // No container passed: with a live view model the store path is unused.
        LiveActivityIntentRunner.completeBakePhase(
            stepTypeID: phases[0].stepTypeID,
            sequenceIndex: phases[0].sequenceIndex,
            router: router
        )

        #expect(phases[0].stepStatus == .done)
        #expect(phases[1].stepStatus == .active)
    }
}
