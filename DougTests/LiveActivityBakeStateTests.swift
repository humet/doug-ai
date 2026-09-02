@testable import Doug
import Foundation
import SwiftData
import Testing

@MainActor
struct LiveActivityBakeStateTests {
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

    /// Active bulk ferment with fold sub-steps (mirrors how the app persists
    /// a schedule), followed by an upcoming shape step.
    private func makeBulkSchedule(
        anchor: Date,
        context: ModelContext
    ) -> (schedule: Schedule, folds: [ScheduleStep]) {
        let schedule = Schedule(
            recipeID: .oliveRosemary,
            targetBreadReadyTime: anchor.addingTimeInterval(20 * 60 * 60),
            kitchenTemperatureCelsius: 24
        )
        schedule.scheduleStatus = .active
        context.insert(schedule)

        let bulk = ScheduleStep(
            stepTypeID: .bulkFerment,
            sequenceIndex: 0,
            computedStartTime: anchor,
            computedEndTime: anchor.addingTimeInterval(240 * 60),
            computedDurationMinutes: 240
        )
        bulk.schedule = schedule
        bulk.stepStatus = .active
        context.insert(bulk)

        var folds: [ScheduleStep] = []
        let foldTypes: [StepTypeID] = [.stretchAndFold, .addInclusions, .stretchAndFold]
        for (index, typeID) in foldTypes.enumerated() {
            let start = anchor.addingTimeInterval(Double(index + 1) * 40 * 60)
            let fold = ScheduleStep(
                stepTypeID: typeID,
                sequenceIndex: index,
                computedStartTime: start,
                computedEndTime: start.addingTimeInterval(2 * 60),
                computedDurationMinutes: 2
            )
            fold.parentStep = bulk
            fold.schedule = schedule
            context.insert(fold)
            folds.append(fold)
        }

        let shape = ScheduleStep(
            stepTypeID: .shape,
            sequenceIndex: 1,
            computedStartTime: bulk.computedEndTime,
            computedEndTime: bulk.computedEndTime.addingTimeInterval(20 * 60),
            computedDurationMinutes: 20
        )
        shape.schedule = schedule
        context.insert(shape)

        return (schedule, folds)
    }

    @Test func bulkFermentCountsDownToFirstPendingFold() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let anchor = Date()
        let (schedule, folds) = makeBulkSchedule(anchor: anchor, context: context)

        let state = LiveActivityService.buildBakeState(from: schedule)

        #expect(state.currentStepLabel == "Bulk Ferment")
        #expect(state.nextFoldLabel == "Stretch & Fold")
        #expect(state.nextFoldTime == folds[0].computedStartTime)
        #expect(state.timerTarget == folds[0].computedStartTime)
        // The step-level fields still describe the whole bulk window.
        #expect(state.stepEndTime == folds[0].parentStep?.computedEndTime)
    }

    @Test func completedFoldAdvancesToNextPendingSubStep() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let anchor = Date()
        let (schedule, folds) = makeBulkSchedule(anchor: anchor, context: context)

        folds[0].stepStatus = .done
        let state = LiveActivityService.buildBakeState(from: schedule)

        #expect(state.nextFoldLabel == "Add Inclusions")
        #expect(state.nextFoldTime == folds[1].computedStartTime)
    }

    @Test func skippedFoldsAreNotOffered() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let anchor = Date()
        let (schedule, folds) = makeBulkSchedule(anchor: anchor, context: context)

        folds[0].stepStatus = .done
        folds[1].stepStatus = .skipped
        let state = LiveActivityService.buildBakeState(from: schedule)

        #expect(state.nextFoldLabel == "Stretch & Fold")
        #expect(state.nextFoldTime == folds[2].computedStartTime)
    }

    @Test func allFoldsDoneFallsBackToStepEnd() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let anchor = Date()
        let (schedule, folds) = makeBulkSchedule(anchor: anchor, context: context)

        for fold in folds {
            fold.stepStatus = .done
        }
        let state = LiveActivityService.buildBakeState(from: schedule)

        #expect(state.nextFoldLabel == nil)
        #expect(state.nextFoldTime == nil)
        #expect(state.timerTarget == folds[0].parentStep?.computedEndTime)
    }

    @Test func timerIntervalClampsToFoldAndNeverInverts() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let anchor = Date()
        let (schedule, folds) = makeBulkSchedule(anchor: anchor, context: context)

        let state = LiveActivityService.buildBakeState(from: schedule)
        #expect(state.timerInterval.upperBound == folds[0].computedStartTime)
        #expect(state.timerInterval.lowerBound <= state.timerInterval.upperBound)

        // Degenerate ordering (fold time before step start) must not produce
        // an invalid range — ClosedRange traps on inverted bounds.
        folds[0].computedStartTime = anchor.addingTimeInterval(-10 * 60)
        let inverted = LiveActivityService.buildBakeState(from: schedule)
        #expect(inverted.timerInterval.lowerBound <= inverted.timerInterval.upperBound)
        #expect(inverted.timerInterval.upperBound == folds[0].computedStartTime)
    }

    /// Active bake step with covered/uncovered phase sub-steps, the covered
    /// phase already running.
    private func makeBakeSchedule(
        anchor: Date,
        context: ModelContext
    ) -> (schedule: Schedule, phases: [ScheduleStep]) {
        let schedule = Schedule(
            recipeID: .oliveRosemary,
            targetBreadReadyTime: anchor.addingTimeInterval(60 * 60),
            kitchenTemperatureCelsius: 24
        )
        schedule.scheduleStatus = .active
        context.insert(schedule)

        let bake = ScheduleStep(
            stepTypeID: .bake,
            sequenceIndex: 0,
            computedStartTime: anchor.addingTimeInterval(-5 * 60),
            computedEndTime: anchor.addingTimeInterval(40 * 60),
            computedDurationMinutes: 45
        )
        bake.schedule = schedule
        bake.stepStatus = .active
        context.insert(bake)

        let covered = ScheduleStep(
            stepTypeID: .bakeCovered,
            sequenceIndex: 0,
            computedStartTime: anchor.addingTimeInterval(-5 * 60),
            computedEndTime: anchor.addingTimeInterval(15 * 60),
            computedDurationMinutes: 20
        )
        covered.parentStep = bake
        covered.schedule = schedule
        covered.stepStatus = .active
        context.insert(covered)

        let uncovered = ScheduleStep(
            stepTypeID: .bakeUncovered,
            sequenceIndex: 1,
            computedStartTime: covered.computedEndTime,
            computedEndTime: covered.computedEndTime.addingTimeInterval(25 * 60),
            computedDurationMinutes: 25
        )
        uncovered.parentStep = bake
        uncovered.schedule = schedule
        context.insert(uncovered)

        return (schedule, [covered, uncovered])
    }

    @Test func runningBakePhaseCountsDownToItsEnd() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let anchor = Date()
        let (schedule, phases) = makeBakeSchedule(anchor: anchor, context: context)

        let state = LiveActivityService.buildBakeState(from: schedule)

        // Counting down to the phase's start would pin the timer at 0:00 —
        // the phase is underway, so the target is its end.
        #expect(state.nextFoldIsRunning)
        #expect(state.nextFoldTime == phases[0].computedEndTime)
        #expect(state.timerTarget == phases[0].computedEndTime)
        // Running phases offer one-tap completion from the widget.
        #expect(state.nextFoldActionLabel == "Lid Removed")
        #expect(state.nextFoldStepTypeID == phases[0].stepTypeID)
        #expect(state.nextFoldSequenceIndex == phases[0].sequenceIndex)
    }

    @Test func uncoveredPhaseOffersBreadOut() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let anchor = Date()
        let (schedule, phases) = makeBakeSchedule(anchor: anchor, context: context)

        phases[0].stepStatus = .done
        phases[1].stepStatus = .active
        let state = LiveActivityService.buildBakeState(from: schedule)

        #expect(state.nextFoldActionLabel == "Bread Out")
    }

    @Test func pendingBakePhaseCountsDownToItsStart() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let anchor = Date()
        let (schedule, phases) = makeBakeSchedule(anchor: anchor, context: context)

        phases[0].stepStatus = .done
        let state = LiveActivityService.buildBakeState(from: schedule)

        #expect(!state.nextFoldIsRunning)
        #expect(state.timerTarget == phases[1].computedStartTime)

        phases[1].stepStatus = .active
        let running = LiveActivityService.buildBakeState(from: schedule)
        #expect(running.nextFoldIsRunning)
        #expect(running.timerTarget == phases[1].computedEndTime)
    }

    @Test func pendingFoldsAreNotRunning() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let anchor = Date()
        let (schedule, folds) = makeBulkSchedule(anchor: anchor, context: context)

        let state = LiveActivityService.buildBakeState(from: schedule)

        // Folds stay `.upcoming` until done/skipped — the countdown still
        // targets their start.
        #expect(!state.nextFoldIsRunning)
        #expect(state.timerTarget == folds[0].computedStartTime)
        // No widget button for folds — they want a temperature reading in-app.
        #expect(state.nextFoldActionLabel == nil)
    }

    @Test func showsActivityDuringActiveBulkFerment() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let anchor = Date()
        let (schedule, _) = makeBulkSchedule(anchor: anchor, context: context)

        #expect(LiveActivityService.shouldShowBakeActivity(for: schedule, now: anchor))
    }

    @Test func hidesActivityForHandsOnStepAndInactiveSchedule() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let anchor = Date()
        let (schedule, folds) = makeBulkSchedule(anchor: anchor, context: context)

        // Hands-on step types never get a Live Activity.
        let bulk = try #require(folds[0].parentStep)
        bulk.stepTypeID = StepTypeID.mix.rawValue
        #expect(!LiveActivityService.shouldShowBakeActivity(for: schedule, now: anchor))

        bulk.stepTypeID = StepTypeID.bulkFerment.rawValue
        schedule.scheduleStatus = .complete
        #expect(!LiveActivityService.shouldShowBakeActivity(for: schedule, now: anchor))
    }

    @Test func longWaitStepsOnlyShowInsideTheFinalHour() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let anchor = Date()
        let (schedule, folds) = makeBulkSchedule(anchor: anchor, context: context)

        let bulk = try #require(folds[0].parentStep)
        bulk.stepTypeID = StepTypeID.coldRetard.rawValue

        // 240-minute step: far from its end the activity stays hidden.
        #expect(!LiveActivityService.shouldShowBakeActivity(for: schedule, now: anchor))
        // Inside the final hour it appears.
        let lateNow = bulk.computedEndTime.addingTimeInterval(-30 * 60)
        #expect(LiveActivityService.shouldShowBakeActivity(for: schedule, now: lateNow))
    }

    @Test func noActiveStepStillShowsActivity() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let anchor = Date()
        let (schedule, folds) = makeBulkSchedule(anchor: anchor, context: context)

        // Between steps (previous done, next not yet promoted) the activity
        // persists, pointing at the upcoming step.
        folds[0].parentStep?.stepStatus = .done
        #expect(LiveActivityService.shouldShowBakeActivity(for: schedule, now: anchor))
    }

    @Test func upcomingBulkStepDoesNotSurfaceFolds() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let anchor = Date()
        let (schedule, folds) = makeBulkSchedule(anchor: anchor, context: context)

        folds[0].parentStep?.stepStatus = .upcoming
        let state = LiveActivityService.buildBakeState(from: schedule)

        #expect(state.nextFoldLabel == nil)
        #expect(state.nextFoldTime == nil)
    }
}
