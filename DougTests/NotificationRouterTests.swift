@testable import Doug
import Foundation
import SwiftData
import Testing

@MainActor
struct NotificationRouterTests {
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

    /// Active schedule with a bake step whose covered/uncovered phases are
    /// sub-steps, mirroring how the app persists them.
    @discardableResult
    private func makeBakeSchedule(anchor: Date, context: ModelContext) -> (Schedule, covered: ScheduleStep) {
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

        return (schedule, covered)
    }

    @Test func bakeDoneBuffersUntilScheduleRestores() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let (_, covered) = makeBakeSchedule(anchor: Date(), context: context)
        try context.save()

        let router = NotificationRouter()
        // Cold launch: the action arrives before any view model exists.
        router.markBakeSubStepDone(
            stepTypeID: StepTypeID.bakeCovered.rawValue,
            sequenceIndex: 0
        )
        #expect(covered.stepStatus != .done)

        // View model registers (as in ScheduleViewModel.init) — schedule not
        // yet restored, so the action must still be pending.
        let vm = ScheduleViewModel()
        router.registerScheduleViewModel(vm)
        #expect(vm.pendingBakeDone != nil)
        #expect(covered.stepStatus != .done)

        // ScheduleTab's .task restores the schedule — the buffered action drains.
        vm.restoreActiveSchedule(modelContext: context)
        #expect(vm.pendingBakeDone == nil)
        #expect(covered.stepStatus == .done)
    }

    @Test func bakeDoneAppliesImmediatelyWhenScheduleIsLive() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let (schedule, covered) = makeBakeSchedule(anchor: Date(), context: context)

        let router = NotificationRouter()
        let vm = ScheduleViewModel()
        vm.activeSchedule = schedule
        router.registerScheduleViewModel(vm)

        router.markBakeSubStepDone(
            stepTypeID: StepTypeID.bakeCovered.rawValue,
            sequenceIndex: 0
        )
        #expect(covered.stepStatus == .done)
        #expect(router.selectedTab == .schedule)
    }

    @Test func requestStarterLogFeedSwitchesTabAndSetsPendingAction() {
        let router = NotificationRouter()
        router.requestStarterLogFeed()
        #expect(router.selectedTab == .starter)
        #expect(router.pendingStarterAction == .logFeed)
    }

    @Test func focusStarterTabSwitchesTab() {
        let router = NotificationRouter()
        router.focusStarterTab()
        #expect(router.selectedTab == .starter)
    }
}
