@testable import Doug
import Foundation
import SwiftData
import Testing

@MainActor
struct ScheduleAdjustmentsTests {
    // MARK: - Helpers

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

    /// Constructs a three-step synthetic schedule (autolyse → mix → bulk) anchored at a specific date.
    /// Lets tests exercise cascade behavior without the full ScheduleBuilder.
    private func makeSchedule(anchor: Date, context: ModelContext) -> (Schedule, [ScheduleStep]) {
        let schedule = Schedule(
            recipeID: .countryLoaf,
            targetBreadReadyTime: anchor.addingTimeInterval(3 * 60 * 60),
            kitchenTemperatureCelsius: 22
        )
        schedule.scheduleStatus = .active
        context.insert(schedule)

        let autolyse = ScheduleStep(
            stepTypeID: .autolyse,
            sequenceIndex: 0,
            computedStartTime: anchor,
            computedEndTime: anchor.addingTimeInterval(45 * 60),
            computedDurationMinutes: 45
        )
        autolyse.schedule = schedule
        autolyse.stepStatus = .active
        context.insert(autolyse)

        let mix = ScheduleStep(
            stepTypeID: .mix,
            sequenceIndex: 1,
            computedStartTime: anchor.addingTimeInterval(45 * 60),
            computedEndTime: anchor.addingTimeInterval(50 * 60),
            computedDurationMinutes: 5
        )
        mix.schedule = schedule
        context.insert(mix)

        let bulk = ScheduleStep(
            stepTypeID: .bulkFerment,
            sequenceIndex: 2,
            computedStartTime: anchor.addingTimeInterval(50 * 60),
            computedEndTime: anchor.addingTimeInterval(170 * 60),
            computedDurationMinutes: 120
        )
        bulk.schedule = schedule
        context.insert(bulk)

        return (schedule, [autolyse, mix, bulk])
    }

    private func makeViewModel(with schedule: Schedule) -> ScheduleViewModel {
        let vm = ScheduleViewModel()
        vm.activeSchedule = schedule
        return vm
    }

    // MARK: - Extend

    @Test func extendStepPushesDownstream() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let anchor = Date(timeIntervalSince1970: 1_700_000_000)
        let (schedule, steps) = makeSchedule(anchor: anchor, context: context)
        let vm = makeViewModel(with: schedule)

        let originalMixStart = steps[1].computedStartTime
        let originalBulkEnd = steps[2].computedEndTime
        let originalTarget = schedule.targetBreadReadyTime

        vm.extendStep(steps[0], byMinutes: 30, modelContext: context)

        #expect(steps[0].computedDurationMinutes == 75)
        #expect(steps[1].computedStartTime == originalMixStart.addingTimeInterval(30 * 60))
        #expect(steps[2].computedEndTime == originalBulkEnd.addingTimeInterval(30 * 60))
        #expect(schedule.targetBreadReadyTime == originalTarget.addingTimeInterval(30 * 60))
    }

    @Test func shortenStepPullsDownstreamForward() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let anchor = Date(timeIntervalSince1970: 1_700_000_000)
        let (schedule, steps) = makeSchedule(anchor: anchor, context: context)
        let vm = makeViewModel(with: schedule)

        let originalBulkStart = steps[2].computedStartTime
        vm.shortenStep(steps[0], byMinutes: 15, modelContext: context)

        #expect(steps[0].computedDurationMinutes == 30)
        #expect(steps[2].computedStartTime == originalBulkStart.addingTimeInterval(-15 * 60))
    }

    // MARK: - Finish Early

    @Test func finishStepEarlyCascadesAndMarksDone() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        // Anchor 10 minutes ago so "now" is 10 minutes into autolyse.
        let anchor = Date().addingTimeInterval(-10 * 60)
        let (schedule, steps) = makeSchedule(anchor: anchor, context: context)
        let vm = makeViewModel(with: schedule)

        let originalMixStart = steps[1].computedStartTime
        vm.finishStepEarly(steps[0], modelContext: context)

        #expect(steps[0].stepStatus == .done)
        #expect(steps[0].actualEndTime != nil)
        // Mix start pulled forward (now < original autolyse end).
        #expect(steps[1].computedStartTime < originalMixStart)
    }

    // MARK: - Start Now

    @Test func startStepNowShiftsDownstream() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        // Anchor 2 hours ago so mix's start (at anchor + 45m) is already in the past.
        let anchor = Date().addingTimeInterval(-2 * 60 * 60)
        let (schedule, steps) = makeSchedule(anchor: anchor, context: context)
        let vm = makeViewModel(with: schedule)

        let originalBulkEnd = steps[2].computedEndTime
        let originalMixStart = steps[1].computedStartTime
        vm.startStepNow(steps[1], modelContext: context)

        // Mix moved forward to now.
        #expect(steps[1].computedStartTime > originalMixStart)
        // Bulk end pushed later by the same delta.
        #expect(steps[2].computedEndTime > originalBulkEnd)
    }

    // MARK: - Pause / Resume

    @Test func pauseSetsMarker() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let (schedule, _) = makeSchedule(anchor: Date(), context: context)
        let vm = makeViewModel(with: schedule)

        vm.pauseSchedule(modelContext: context)
        #expect(schedule.pausedAt != nil)
    }

    // MARK: - advanceIfReady

    @Test func advanceIfReadyStopsAtPassiveFlexibleAndHandsOn() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        // Anchor so autolyse already ended 1 minute ago.
        let anchor = Date().addingTimeInterval(-46 * 60)
        let (schedule, steps) = makeSchedule(anchor: anchor, context: context)
        let vm = makeViewModel(with: schedule)

        vm.advanceIfReady(now: Date(), modelContext: context)

        // Autolyse (passiveFlexible) stays active past its timer — requires user confirmation.
        #expect(steps[0].stepStatus == .active)
        #expect(steps[0].actualEndTime == nil)
        // Mix stays upcoming until autolyse is manually confirmed.
        #expect(steps[1].stepStatus == .upcoming)
        #expect(steps[2].stepStatus == .upcoming)
    }

    @Test func advanceIfReadyDoesNotAutoCompleteBulkFerment() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        // Anchor so all three steps ended in the past.
        let anchor = Date().addingTimeInterval(-180 * 60)
        let (schedule, steps) = makeSchedule(anchor: anchor, context: context)
        // Manually advance past autolyse and mix so bulk (passiveFixed) is active.
        steps[0].stepStatus = .done
        steps[0].actualEndTime = steps[0].computedEndTime
        steps[1].stepStatus = .done
        steps[1].actualEndTime = steps[1].computedEndTime
        steps[2].stepStatus = .active
        let vm = makeViewModel(with: schedule)

        vm.advanceIfReady(now: Date(), modelContext: context)

        // Bulk ferment requires baker judgment — stays active past timer.
        #expect(steps[2].stepStatus == .active)
        #expect(steps[2].actualEndTime == nil)
    }

    @Test func advanceIfReadyWaitsOnUnconfirmedHandsOn() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        // Anchor so mix end is 1 minute in the past but mix is still active.
        let anchor = Date().addingTimeInterval(-51 * 60)
        let (schedule, steps) = makeSchedule(anchor: anchor, context: context)
        steps[0].stepStatus = .done
        steps[0].actualEndTime = steps[0].computedEndTime
        steps[1].stepStatus = .active
        let vm = makeViewModel(with: schedule)

        vm.advanceIfReady(now: Date(), modelContext: context)

        // Hands-on mix stays active even past its end.
        #expect(steps[1].stepStatus == .active)
        #expect(steps[2].stepStatus == .upcoming)
    }

    // MARK: - Bake substeps

    private func makeBakeSchedule(anchor: Date, context: ModelContext) -> (Schedule, ScheduleStep, [ScheduleStep]) {
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

        return (schedule, bake, [covered, uncovered])
    }

    @Test func advanceSubStepsAdvancesBakePhases() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let anchor = Date().addingTimeInterval(-25 * 60)
        let (schedule, _, subs) = makeBakeSchedule(anchor: anchor, context: context)
        let vm = makeViewModel(with: schedule)

        vm.advanceIfReady(now: Date(), modelContext: context)

        // Covered is overdue but stays active — no auto-skipping for bake phases.
        #expect(subs[0].stepStatus == .active)
        #expect(subs[1].stepStatus == .upcoming)
    }

    @Test func bakeParentCompletesWhenAllSubStepsDone() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let anchor = Date().addingTimeInterval(-50 * 60)
        let (schedule, bake, subs) = makeBakeSchedule(anchor: anchor, context: context)
        subs[0].stepStatus = .done
        subs[0].actualEndTime = subs[0].computedEndTime
        subs[1].stepStatus = .done
        subs[1].actualEndTime = subs[1].computedEndTime
        let vm = makeViewModel(with: schedule)

        vm.advanceIfReady(now: Date(), modelContext: context)

        #expect(bake.stepStatus == .done)
    }

    @Test func bakeParentStaysActiveWithPendingSubSteps() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let anchor = Date().addingTimeInterval(-50 * 60)
        let (schedule, bake, subs) = makeBakeSchedule(anchor: anchor, context: context)
        subs[0].stepStatus = .done
        subs[0].actualEndTime = subs[0].computedEndTime
        // Uncovered still active
        subs[1].stepStatus = .active
        let vm = makeViewModel(with: schedule)

        vm.advanceIfReady(now: Date(), modelContext: context)

        // Parent stays active because uncovered isn't done yet.
        #expect(bake.stepStatus == .active)
    }

    @Test func markStepDoneCascadesLateBakeSubStep() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let anchor = Date().addingTimeInterval(-25 * 60)
        let (schedule, bake, subs) = makeBakeSchedule(anchor: anchor, context: context)
        let vm = makeViewModel(with: schedule)

        let originalUncoveredStart = subs[1].computedStartTime

        vm.markStepDone(subs[0], modelContext: context)

        // Covered was 5 min overdue, so uncovered should shift later.
        #expect(subs[0].stepStatus == .done)
        #expect(subs[1].computedStartTime > originalUncoveredStart)
        // Parent end time should also have shifted.
        #expect(bake.computedEndTime > anchor.addingTimeInterval(45 * 60))
    }

    // MARK: - markStepDone / reopenStep

    @Test func markStepDonePromotesNext() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let (schedule, steps) = makeSchedule(anchor: Date(), context: context)
        steps[0].stepStatus = .done
        steps[0].actualEndTime = Date()
        steps[1].stepStatus = .active
        let vm = makeViewModel(with: schedule)

        vm.markStepDone(steps[1], modelContext: context)

        #expect(steps[1].stepStatus == .done)
        #expect(steps[1].actualEndTime != nil)
        // Bulk (next step) flips to active.
        #expect(steps[2].stepStatus == .active)
    }

    @Test func reopenStepRevertsStatusOnly() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let (schedule, steps) = makeSchedule(anchor: Date(), context: context)
        steps[0].stepStatus = .done
        steps[0].actualEndTime = Date()
        steps[1].stepStatus = .active
        let vm = makeViewModel(with: schedule)

        let originalAutolyseStart = steps[0].computedStartTime
        let originalAutolyseEnd = steps[0].computedEndTime

        vm.reopenStep(steps[0], modelContext: context)

        #expect(steps[0].stepStatus == .active)
        #expect(steps[0].actualEndTime == nil)
        // Previously-active mix demoted back to upcoming.
        #expect(steps[1].stepStatus == .upcoming)
        // Planned times untouched.
        #expect(steps[0].computedStartTime == originalAutolyseStart)
        #expect(steps[0].computedEndTime == originalAutolyseEnd)
    }
}

// MARK: - Step type copy coverage

struct StepTypeCopyTests {
    @Test func everyStepTypeHasCompleteCopy() {
        for id in StepTypeID.allCases {
            let type = StepTypeRegistry.type(for: id)
            #expect(!type.instructionText.isEmpty, "Missing instructionText for \(id.rawValue)")
            #expect(!type.notificationText.isEmpty, "Missing notificationText for \(id.rawValue)")
            #expect(!type.successSignal.isEmpty, "Missing successSignal for \(id.rawValue)")
        }
    }
}
