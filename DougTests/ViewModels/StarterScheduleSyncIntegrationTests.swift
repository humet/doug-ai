@testable import Doug
import Foundation
import SwiftData
import Testing

/// End-to-end checks that Starter-tab events drive a live schedule's
/// activation preamble through `ScheduleViewModel.handleStarterEvent`.
/// Calls the handler directly rather than via NotificationCenter so the tests
/// stay synchronous.
@MainActor
@Suite(.serialized)
struct StarterScheduleSyncIntegrationTests {
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

    private struct PreambleFixture {
        let schedule: Schedule
        let filler: ScheduleStep
        let activate: ScheduleStep
        let wait: ScheduleStep
        let build: ScheduleStep
    }

    /// A persisted active schedule with a dormant-starter preamble:
    /// fridgeRest (active) → activateStarter → waitForPeak → buildLevain.
    private func makePreambleSchedule(
        anchor: Date,
        context: ModelContext
    ) -> PreambleFixture {
        let schedule = Schedule(
            recipeID: .countryLoaf,
            targetBreadReadyTime: anchor.addingTimeInterval(24 * 3600),
            kitchenTemperatureCelsius: 22
        )
        schedule.scheduleStatus = .active
        context.insert(schedule)

        func step(_ id: StepTypeID, _ index: Int, start: TimeInterval, end: TimeInterval) -> ScheduleStep {
            let step = ScheduleStep(
                stepTypeID: id,
                sequenceIndex: index,
                computedStartTime: anchor.addingTimeInterval(start),
                computedEndTime: anchor.addingTimeInterval(end),
                computedDurationMinutes: (end - start) / 60
            )
            step.schedule = schedule
            context.insert(step)
            return step
        }

        let filler = step(.fridgeRest, 0, start: 0, end: 2 * 3600)
        filler.stepStatus = .active
        let activate = step(.activateStarter, 1, start: 2 * 3600, end: 2 * 3600 + 600)
        let wait = step(.waitForPeak, 2, start: 2 * 3600 + 600, end: 8 * 3600)
        let build = step(.buildLevain, 3, start: 8 * 3600, end: 8 * 3600 + 900)

        return PreambleFixture(schedule: schedule, filler: filler, activate: activate, wait: wait, build: build)
    }

    private func makeProfile(
        lifecycle: StarterLifecycleState,
        context: ModelContext
    ) -> StarterProfile {
        let profile = StarterProfile(storageType: .fridge)
        profile.starterLifecycleState = lifecycle
        profile.activePeakAverageMinutes = 360
        context.insert(profile)
        return profile
    }

    @Test func activatedEventCompletesFillerAndStartsActivateStep() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let anchor = Date().addingTimeInterval(-10 * 60)
        let fixture = makePreambleSchedule(anchor: anchor, context: context)
        let (schedule, filler, activate) = (fixture.schedule, fixture.filler, fixture.activate)
        _ = makeProfile(lifecycle: .activating, context: context)
        let vm = ScheduleViewModel()
        vm.activeSchedule = schedule

        vm.handleStarterEvent(.activated(at: Date()))

        #expect(filler.stepStatus == .done)
        #expect(activate.stepStatus == .active)
    }

    @Test func activationFeedCompletesPreambleRetimesWaitAndLogsNoDuplicateFeed() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let anchor = Date().addingTimeInterval(-10 * 60)
        let fixture = makePreambleSchedule(anchor: anchor, context: context)
        let (schedule, filler, activate, wait) = (fixture.schedule, fixture.filler, fixture.activate, fixture.wait)
        _ = makeProfile(lifecycle: .activating, context: context)

        // The user's own activation feed — the only one that should ever exist.
        let feedTime = Date()
        let userFeed = StarterFeedLog(
            timestamp: feedTime,
            ratioStarter: 1, ratioFlour: 5, ratioWater: 5,
            kitchenTemperatureCelsius: 22,
            feedIntent: .activation
        )
        context.insert(userFeed)

        let vm = ScheduleViewModel()
        vm.activeSchedule = schedule

        vm.handleStarterEvent(.activationFeedLogged(at: feedTime))

        #expect(filler.stepStatus == .done)
        #expect(activate.stepStatus == .done)

        // The wait now ends one expected-peak from the actual feed time.
        let expectedEnd = feedTime.addingTimeInterval(360 * 60)
        #expect(abs(wait.computedEndTime.timeIntervalSince(expectedEnd)) < 1)

        // Sync-driven completion must not auto-log a second activation feed.
        let logs = try context.fetch(FetchDescriptor<StarterFeedLog>())
        #expect(logs.count == 1)
    }

    @Test func backdatedPeakCompletesWaitAndPullsDownstreamForward() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let now = Date()
        let anchor = now.addingTimeInterval(-6 * 3600)
        let fixture = makePreambleSchedule(anchor: anchor, context: context)
        let (schedule, filler, activate, wait, build) = (
            fixture.schedule,
            fixture.filler,
            fixture.activate,
            fixture.wait,
            fixture.build
        )
        filler.stepStatus = .done
        activate.stepStatus = .done
        wait.stepStatus = .active
        _ = makeProfile(lifecycle: .activating, context: context)

        // An unpeaked activation feed: handleStarterEvent suppresses starter
        // side effects, so it must stay unpeaked (the StarterViewModel already
        // handled it before posting the event).
        let feed = StarterFeedLog(
            timestamp: anchor.addingTimeInterval(2 * 3600),
            ratioStarter: 1, ratioFlour: 5, ratioWater: 5,
            kitchenTemperatureCelsius: 22,
            feedIntent: .activation
        )
        context.insert(feed)

        let vm = ScheduleViewModel()
        vm.activeSchedule = schedule

        let backdated = now.addingTimeInterval(-1 * 3600)
        vm.handleStarterEvent(.peakMarked(at: backdated, intent: .activation))

        #expect(wait.stepStatus == .done)
        #expect(wait.actualEndTime == backdated)
        // The wait originally ended at anchor+8h (= now+2h); completing it at
        // now-1h pulls Build Levain forward by the same 3 hours.
        #expect(abs(build.computedStartTime.timeIntervalSince(backdated)) < 1)
        #expect(feed.peakTimestamp == nil)
    }

    @Test func maintenancePeakLeavesScheduleUntouched() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let anchor = Date().addingTimeInterval(-10 * 60)
        let fixture = makePreambleSchedule(anchor: anchor, context: context)
        let (schedule, filler, activate, wait) = (fixture.schedule, fixture.filler, fixture.activate, fixture.wait)
        _ = makeProfile(lifecycle: .dormant, context: context)
        let vm = ScheduleViewModel()
        vm.activeSchedule = schedule

        vm.handleStarterEvent(.peakMarked(at: Date(), intent: .maintenance))

        #expect(filler.stepStatus == .active)
        #expect(activate.stepStatus == .upcoming)
        #expect(wait.stepStatus == .upcoming)
    }

    // MARK: - markStepDone side-effect regressions

    @Test func markStepDoneWithoutProfileStillMarksPeakAndTransitions() throws {
        // Regression for the notification-action / detail-sheet path that used
        // to pass starterProfile: nil and leave the starter stuck in
        // `.activating` with an unpeaked feed.
        let container = try makeContainer()
        let context = ModelContext(container)
        let now = Date()
        let anchor = now.addingTimeInterval(-6 * 3600)
        let fixture = makePreambleSchedule(anchor: anchor, context: context)
        let (schedule, filler, activate, wait) = (fixture.schedule, fixture.filler, fixture.activate, fixture.wait)
        filler.stepStatus = .done
        activate.stepStatus = .done
        wait.stepStatus = .active
        let profile = makeProfile(lifecycle: .activating, context: context)
        profile.activePeakAverageMinutes = nil

        let feed = StarterFeedLog(
            timestamp: now.addingTimeInterval(-6 * 3600),
            ratioStarter: 1, ratioFlour: 5, ratioWater: 5,
            kitchenTemperatureCelsius: 22,
            feedIntent: .activation
        )
        context.insert(feed)

        let vm = ScheduleViewModel()
        vm.activeSchedule = schedule

        vm.markStepDone(wait, modelContext: context)

        #expect(profile.starterLifecycleState == .active)
        #expect(feed.peakTimestamp != nil)

        // Averages come from the shared full recompute (~360 min for a 6h
        // rise), not a running (avg + peak) / 2.
        let active = try #require(profile.activePeakAverageMinutes)
        #expect(abs(active - 360) < 1)
    }
}
