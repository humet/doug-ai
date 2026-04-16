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

    // UI state
    var showConflictSheet = false
    var showColdRetardSlider = false
    var showTemperatureEntry = false
    var selectedFoldStep: ScheduleStep?
    var starterHealthBlock: StarterHealthStatus?
    var pendingFoldEntry: PendingFoldEntry?

    init() {
        NotificationRouter.shared.registerScheduleViewModel(self)
    }

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
            showConflictSheet = true
        }
    }

    // MARK: - Apply Conflict Resolution Option

    /// Applies a user-selected conflict-resolution option and re-runs the builder.
    /// If the option carries a structured target-time shift, the target moves and the
    /// preview rebuilds; the sheet either dismisses on success or reopens on a fresh conflict.
    func apply(
        option: ConflictOption,
        availability: UserAvailability?,
        windows: [UnavailableWindow]
    ) {
        showConflictSheet = false
        if let shift = option.targetTimeShiftMinutes {
            targetDate = targetDate.addingTimeInterval(shift * 60)
        }
        buildPreview(availability: availability, windows: windows)
    }

    // MARK: - Pre-Bake Health Check

    /// Checks starter health before allowing bake to start.
    /// Returns true if bake can proceed, false if blocked.
    func preBakeHealthCheck(
        profile: StarterProfile?,
        feedLogs: [StarterFeedLog]
    ) -> Bool {
        guard let profile else {
            starterHealthBlock = .needsFeed
            return false
        }

        let profileInput = StarterProfileInput(from: profile)
        let logInputs = feedLogs.map { FeedLogInput(from: $0) }
        let status = StarterHealthAssessor.assess(profile: profileInput, feedLogs: logInputs)

        switch status {
        case .readyToBake:
            starterHealthBlock = nil
            return true
        case .needsFeed:
            starterHealthBlock = .needsFeed
            return false
        case .needsRevival:
            starterHealthBlock = .needsRevival
            return false
        }
    }

    // MARK: - Start Bake

    func startBake(modelContext: ModelContext) {
        guard !previewSteps.isEmpty else { return }

        let schedule = Schedule(
            recipeID: selectedRecipeID,
            targetBreadReadyTime: targetDate,
            kitchenTemperatureCelsius: kitchenTemperature
        )
        schedule.scheduleStatus = .active
        modelContext.insert(schedule)

        var persistedSteps: [ScheduleStep] = []

        for (index, step) in previewSteps.enumerated() {
            let scheduleStep = ScheduleStep(
                stepTypeID: step.stepTypeID,
                sequenceIndex: index,
                computedStartTime: step.startTime,
                computedEndTime: step.endTime,
                computedDurationMinutes: step.durationMinutes
            )
            scheduleStep.schedule = schedule
            persistedSteps.append(scheduleStep)

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
                persistedSteps.append(sub)
            }
        }

        activeSchedule = schedule

        // Schedule notifications
        Task {
            await NotificationService.shared.scheduleNotifications(for: persistedSteps)
        }
    }

    // MARK: - Cold Retard Adjustment

    func adjustColdRetard(to newDurationMinutes: Double, modelContext: ModelContext) {
        guard let schedule = activeSchedule else { return }

        let steps = schedule.steps.sorted { $0.sequenceIndex < $1.sequenceIndex }
        guard let coldRetardStep = steps.first(where: {
            StepTypeID(rawValue: $0.stepTypeID) == .coldRetard
        }) else { return }

        let oldEnd = coldRetardStep.computedEndTime
        let newEnd = coldRetardStep.computedStartTime.addingTimeInterval(newDurationMinutes * 60)
        let delta = newEnd.timeIntervalSince(oldEnd)

        coldRetardStep.computedEndTime = newEnd
        coldRetardStep.computedDurationMinutes = newDurationMinutes

        // Cascade delta to all downstream steps
        for step in steps where step.computedStartTime >= oldEnd {
            step.computedStartTime = step.computedStartTime.addingTimeInterval(delta)
            step.computedEndTime = step.computedEndTime.addingTimeInterval(delta)
        }

        // Update target bread-ready time
        schedule.targetBreadReadyTime = schedule.targetBreadReadyTime.addingTimeInterval(delta)

        // Reschedule notifications
        Task {
            await NotificationService.shared.rescheduleNotifications(for: steps)
        }
    }

    // MARK: - Degree-Hour Schedule Correction

    func handleNewTemperatureReading(schedule: Schedule) {
        let readings = schedule.temperatureReadings.sorted { $0.timestamp < $1.timestamp }
        guard readings.count >= 2 else { return }

        let pairs = readings.map {
            (timestamp: $0.timestamp, temperatureCelsius: $0.temperatureCelsius)
        }
        let currentDH = DegreeHourCalculator.accumulatedDegreeHours(readings: pairs)
        let target = schedule.recipe.degreeHourTarget
        let latestTemp = readings.last!.temperatureCelsius

        guard let remainingMinutes = DegreeHourCalculator.estimatedMinutesRemaining(
            currentDegreeHours: currentDH,
            targetDegreeHours: target,
            latestTempCelsius: latestTemp
        ) else { return }

        // Find bulk ferment step and adjust its end time
        let steps = schedule.steps.sorted { $0.sequenceIndex < $1.sequenceIndex }
        guard let bulkStep = steps.first(where: {
            StepTypeID(rawValue: $0.stepTypeID) == .bulkFerment
        }) else { return }

        let newBulkEnd = Date().addingTimeInterval(remainingMinutes * 60)
        let oldBulkEnd = bulkStep.computedEndTime
        let delta = newBulkEnd.timeIntervalSince(oldBulkEnd)

        // Only correct if the change is significant (>10 minutes)
        guard abs(delta) > 600 else { return }

        bulkStep.computedEndTime = newBulkEnd
        bulkStep.computedDurationMinutes = newBulkEnd.timeIntervalSince(bulkStep.computedStartTime) / 60

        // Cascade to downstream steps
        for step in steps where step.computedStartTime >= oldBulkEnd {
            step.computedStartTime = step.computedStartTime.addingTimeInterval(delta)
            step.computedEndTime = step.computedEndTime.addingTimeInterval(delta)
        }

        schedule.targetBreadReadyTime = schedule.targetBreadReadyTime.addingTimeInterval(delta)

        // Reschedule notifications
        Task {
            await NotificationService.shared.rescheduleNotifications(for: steps)
        }
    }

    // MARK: - Cold Retard Step Lookup

    var coldRetardStep: ScheduleStep? {
        activeSchedule?.steps.first(where: {
            StepTypeID(rawValue: $0.stepTypeID) == .coldRetard
        })
    }

    var coldRetardFlexRange: ClosedRange<Double>? {
        let recipe = activeSchedule.map { RecipeBook.recipe(for: RecipeID(rawValue: $0.recipeID)!) }
        let coldRetardMethod = recipe?.method.first(where: { $0.stepTypeID == .coldRetard })
        return coldRetardMethod?.effectiveFlexRange
    }
}
