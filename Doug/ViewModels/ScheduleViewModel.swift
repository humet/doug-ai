import Foundation
import SwiftData
import Observation

@Observable
@MainActor
final class ScheduleViewModel {
    var selectedRecipeID: RecipeID = .countryLoaf
    var targetDate: Date = {
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) ?? tomorrow
    }()
    var kitchenTemperature: Double = 22.0

    var previewSteps: [ScheduledStep] = []
    var conflict: ScheduleConflict?
    var isBuilding = false

    var activeSchedule: Schedule?

    var selectedRecipe: Recipe {
        RecipeBook.recipe(for: selectedRecipeID)
    }

    // MARK: - Schedule Building

    func buildPreview(
        availability: UserAvailability?,
        windows: [UnavailableWindow]
    ) {
        let avail = availability.map { AvailabilityInput(from: $0) }
            ?? AvailabilityInput(startHour: 6, startMinute: 30, endHour: 21, endMinute: 0)

        let windowInputs = windows.map { WindowInput(from: $0) }

        let input = ScheduleBuilderInput(
            recipe: selectedRecipe,
            targetBreadReadyTime: targetDate,
            kitchenTemperatureCelsius: kitchenTemperature,
            availability: avail,
            unavailableWindows: windowInputs
        )

        let result = ScheduleBuilder.build(input)

        switch result {
        case .success(let steps):
            previewSteps = steps
            conflict = nil
        case .conflict(let scheduleConflict):
            previewSteps = []
            conflict = scheduleConflict
        }
    }

    func startBake(modelContext: ModelContext) {
        guard !previewSteps.isEmpty else { return }

        let schedule = Schedule(
            recipeID: selectedRecipeID,
            targetBreadReadyTime: targetDate,
            kitchenTemperatureCelsius: kitchenTemperature
        )
        schedule.scheduleStatus = .active
        modelContext.insert(schedule)

        for (index, step) in previewSteps.enumerated() {
            let scheduleStep = ScheduleStep(
                stepTypeID: step.stepTypeID,
                sequenceIndex: index,
                computedStartTime: step.startTime,
                computedEndTime: step.endTime,
                computedDurationMinutes: step.durationMinutes
            )
            scheduleStep.schedule = schedule

            // Persist sub-steps (folds)
            for (subIndex, subStep) in step.subSteps.enumerated() {
                let sub = ScheduleStep(
                    stepTypeID: subStep.stepTypeID,
                    sequenceIndex: subIndex,
                    computedStartTime: subStep.startTime,
                    computedEndTime: subStep.endTime,
                    computedDurationMinutes: subStep.durationMinutes
                )
                sub.parentStep = scheduleStep
                sub.schedule = schedule
            }
        }

        activeSchedule = schedule
    }

}
