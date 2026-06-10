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
