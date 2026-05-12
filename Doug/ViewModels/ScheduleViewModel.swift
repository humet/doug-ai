import Foundation
import Observation
import SwiftData

struct ActiveConflict: Identifiable {
    let id = UUID()
    let stepLabel: String
    let stepSequenceIndex: Int
    let scheduledStart: Date
    let scheduledEnd: Date
}

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
    var activeConflicts: [ActiveConflict] = []

    // UI state
    var showConflictSheet = false
    var showColdRetardSlider = false
    var showTemperatureEntry = false
    var showRecipeDetailSheet = false
    var selectedFoldStep: ScheduleStep?
    var starterHealthBlock: StarterHealthStatus?
    var pendingFoldEntry: PendingFoldEntry?
    var pendingStepDetail: PendingStepDetail?

    // Levain-in-progress detection
    var detectedLevain: LevainContext?
    var useActiveLevain = false

    init() {
        NotificationRouter.shared.registerScheduleViewModel(self)
    }

    var selectedRecipe: Recipe {
        RecipeBook.recipe(for: selectedRecipeID)
    }

    // MARK: - Restoration

    func restoreActiveSchedule(modelContext: ModelContext) {
        guard activeSchedule == nil else { return }
        let descriptor = FetchDescriptor<Schedule>(
            predicate: #Predicate { $0.status == "active" }
        )
        activeSchedule = try? modelContext.fetch(descriptor).first
        if let schedule = activeSchedule {
            syncLiveActivity()
            validateConflicts(in: schedule)
        }
    }

    private func cleanupStaleSchedules(modelContext: ModelContext) {
        let descriptor = FetchDescriptor<Schedule>(
            predicate: #Predicate { $0.status != "complete" }
        )
        guard let stale = try? modelContext.fetch(descriptor) else { return }
        for schedule in stale {
            let steps = allSteps(in: schedule)
            NotificationService.shared.cancelNotifications(for: steps)
            modelContext.delete(schedule)
        }
    }

    // MARK: - Schedule Building

    func buildPreview(
        availability: UserAvailability?,
        windows: [UnavailableWindow],
        feedLogs: [StarterFeedLog] = []
    ) {
        let avail = availability.map { AvailabilityInput(from: $0) }
            ?? AvailabilityInput(startHour: 6, startMinute: 30, endHour: 21, endMinute: 0)

        let windowInputs = windows.map { WindowInput(from: $0) }
        let peakProfile = feedLogs.isEmpty
            ? nil
            : StarterPeakProfile(feedLogs: feedLogs.map { FeedLogInput(from: $0) })

        detectActiveLevain(feedLogs: feedLogs, peakProfile: peakProfile)

        let input = ScheduleBuilderInput(
            recipe: selectedRecipe,
            targetBreadReadyTime: targetDate,
            kitchenTemperatureCelsius: kitchenTemperature,
            availability: avail,
            unavailableWindows: windowInputs,
            peakProfile: peakProfile,
            levainContext: useActiveLevain ? detectedLevain : nil
        )

        let result = ScheduleBuilder.build(input)

        switch result {
        case let .success(steps):
            previewSteps = steps
            conflict = nil
        case let .conflict(scheduleConflict):
            previewSteps = []
            conflict = scheduleConflict
            showConflictSheet = true
        }
    }

    private func detectActiveLevain(
        feedLogs: [StarterFeedLog],
        peakProfile: StarterPeakProfile?
    ) {
        guard let latest = feedLogs.first,
              latest.peakTimestamp == nil
        else {
            detectedLevain = nil
            return
        }

        let tempBracket = TemperatureBracket.bracket(celsius: latest.kitchenTemperatureCelsius)
        let ratioBucket = FeedRatioBucket.bucket(
            starter: latest.ratioStarter,
            flour: latest.ratioFlour,
            water: latest.ratioWater
        )

        let expectedPeak: Double = if let bucket = ratioBucket,
                                      let profile = peakProfile,
                                      let observed = profile.averageMinutes(ratio: bucket, tempBracket: tempBracket)
        {
            observed
        } else {
            TemperatureCalculator.levainBuildMinutes(
                kitchenTemp: latest.kitchenTemperatureCelsius
            )
        }

        let elapsed = Date().timeIntervalSince(latest.timestamp) / 60.0
        guard elapsed < expectedPeak * 1.5 else {
            detectedLevain = nil
            return
        }

        detectedLevain = LevainContext(
            fedAt: latest.timestamp,
            expectedPeakMinutes: expectedPeak,
            kitchenTemperatureCelsius: latest.kitchenTemperatureCelsius
        )
    }

    // MARK: - Apply Conflict Resolution Option

    /// Applies a user-selected conflict-resolution option and re-runs the builder.
    /// If the option carries a structured target-time shift, the target moves and the
    /// preview rebuilds; the sheet either dismisses on success or reopens on a fresh conflict.
    func apply(
        option: ConflictOption,
        availability: UserAvailability?,
        windows: [UnavailableWindow],
        feedLogs: [StarterFeedLog] = []
    ) {
        showConflictSheet = false
        if let shift = option.targetTimeShiftMinutes {
            targetDate = targetDate.addingTimeInterval(shift * 60)
        }
        buildPreview(availability: availability, windows: windows, feedLogs: feedLogs)
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

        cleanupStaleSchedules(modelContext: modelContext)

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

        if useActiveLevain {
            promoteNextUpcoming(in: schedule)
        }

        Task {
            await NotificationService.shared.scheduleNotifications(for: persistedSteps)
        }
        syncLiveActivity()
    }

    // MARK: - Cold Retard Adjustment

    func adjustColdRetard(to newDurationMinutes: Double, modelContext _: ModelContext) {
        guard let schedule = activeSchedule else { return }

        let steps = allSteps(in: schedule)
        guard let coldRetardStep = steps.first(where: {
            StepTypeID(rawValue: $0.stepTypeID) == .coldRetard
        }) else { return }

        let oldEnd = coldRetardStep.computedEndTime
        let newEnd = coldRetardStep.computedStartTime.addingTimeInterval(newDurationMinutes * 60)
        let delta = newEnd.timeIntervalSince(oldEnd)

        coldRetardStep.computedEndTime = newEnd
        coldRetardStep.computedDurationMinutes = newDurationMinutes

        cascade(afterEnd: oldEnd, delta: delta, in: schedule)
        syncLiveActivity()
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
        let steps = allSteps(in: schedule)
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

        cascade(afterEnd: oldBulkEnd, delta: delta, in: schedule)
        syncLiveActivity()
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

    // MARK: - Per-step adjustment controls

    /// Marks a hands-on step complete and advances to the next step.
    /// Used when the user confirms "Mark Step Done" on a hands-on step.
    func markStepDone(_ step: ScheduleStep, modelContext _: ModelContext) {
        guard let schedule = activeSchedule else { return }
        step.stepStatus = .done
        if step.actualEndTime == nil {
            step.actualEndTime = Date()
        }
        promoteNextUpcoming(in: schedule)
        syncLiveActivity()
    }

    /// Reverts the most-recently-completed step to active without moving any times.
    func reopenStep(_ step: ScheduleStep, modelContext _: ModelContext) {
        guard let schedule = activeSchedule else { return }
        guard step.stepStatus == .done || step.stepStatus == .skipped else { return }

        let steps = allSteps(in: schedule)
        for candidate in steps where candidate.stepStatus == .active {
            candidate.stepStatus = .upcoming
        }

        let now = Date()
        let oldEnd = step.computedEndTime
        step.stepStatus = .active
        step.actualEndTime = nil

        if step.computedEndTime <= now {
            let duration = step.computedDurationMinutes * 60
            step.computedStartTime = now
            step.computedEndTime = now.addingTimeInterval(duration)
            cascade(
                afterEnd: oldEnd,
                delta: step.computedEndTime.timeIntervalSince(oldEnd),
                in: schedule,
                excluding: step
            )
        }

        syncLiveActivity()
    }

    /// Auto-completes passive steps whose end time has passed and promotes the next
    /// step to `.active`. Also advances fold substeps within the active parent step.
    func advanceIfReady(now: Date, modelContext _: ModelContext) {
        guard let schedule = activeSchedule, schedule.pausedAt == nil else { return }
        let steps = orderedTopLevelSteps(in: schedule)
        var didChange = false

        for step in steps {
            switch step.stepStatus {
            case .done, .skipped:
                continue
            case .upcoming:
                if didChange {
                    promoteNextUpcoming(in: schedule)
                    syncLiveActivity()
                }
                advanceSubSteps(in: schedule, now: now)
                return
            case .active:
                if step.stepType.classification != .handsOn, step.computedEndTime <= now {
                    step.stepStatus = .done
                    step.actualEndTime = step.computedEndTime
                    didChange = true
                    continue
                }
                if didChange {
                    promoteNextUpcoming(in: schedule)
                    syncLiveActivity()
                }
                advanceSubSteps(in: schedule, now: now)
                return
            }
        }
        if didChange {
            promoteNextUpcoming(in: schedule)
            syncLiveActivity()
        }
    }

    private func advanceSubSteps(in schedule: Schedule, now: Date) {
        let steps = orderedTopLevelSteps(in: schedule)
        guard let active = steps.first(where: { $0.stepStatus == .active }),
              !active.subSteps.isEmpty else { return }

        let subs = active.subSteps.sorted { $0.sequenceIndex < $1.sequenceIndex }
        let spacing: TimeInterval = subs.count >= 2
            ? subs[1].computedStartTime.timeIntervalSince(subs[0].computedStartTime)
            : 30 * 60
        let minimumGap = max(spacing / 2, 15 * 60)

        for (index, sub) in subs.enumerated() {
            switch sub.stepStatus {
            case .done, .skipped:
                continue
            case .active, .upcoming:
                let tooLate: Bool
                if index + 1 < subs.count {
                    tooLate = subs[index + 1].computedStartTime <= now
                } else {
                    tooLate = now.timeIntervalSince(sub.computedStartTime) > spacing
                }

                if tooLate {
                    sub.stepStatus = .skipped
                    continue
                }

                if sub.stepStatus == .upcoming, sub.computedStartTime <= now {
                    let isFold = sub.stepTypeID == StepTypeID.stretchAndFold.rawValue
                    if isFold,
                       let prevFold = subs[0 ..< index].last(where: {
                           $0.stepStatus == .done && $0.stepTypeID == StepTypeID.stretchAndFold.rawValue
                       }),
                       let doneTime = prevFold.actualEndTime,
                       now.timeIntervalSince(doneTime) < minimumGap {
                        return
                    }
                    if !subs.contains(where: { $0.stepStatus == .active }) {
                        sub.stepStatus = .active
                    }
                }
                return
            }
        }
    }

    // MARK: - Pause / Resume

    func pauseSchedule(modelContext _: ModelContext) {
        guard let schedule = activeSchedule, schedule.pausedAt == nil else { return }
        schedule.pausedAt = Date()
        let steps = allSteps(in: schedule)
        NotificationService.shared.cancelNotifications(for: steps)
        syncLiveActivity()
    }

    func resumeSchedule(modelContext _: ModelContext) {
        guard let schedule = activeSchedule, let pausedAt = schedule.pausedAt else { return }
        let delta = Date().timeIntervalSince(pausedAt)
        schedule.pausedAt = nil
        guard delta > 0 else {
            let steps = allSteps(in: schedule)
            Task { await NotificationService.shared.rescheduleNotifications(for: steps) }
            syncLiveActivity()
            return
        }
        let steps = allSteps(in: schedule)
        for step in steps where step.stepStatus == .upcoming || step.stepStatus == .active {
            step.computedStartTime = step.computedStartTime.addingTimeInterval(delta)
            step.computedEndTime = step.computedEndTime.addingTimeInterval(delta)
        }
        schedule.targetBreadReadyTime = schedule.targetBreadReadyTime.addingTimeInterval(delta)
        Task { await NotificationService.shared.rescheduleNotifications(for: steps) }
        syncLiveActivity()
    }

    // MARK: - Finish Early / Start Now / Extend / Shorten

    func finishStepEarly(_ step: ScheduleStep, modelContext _: ModelContext) {
        guard let schedule = activeSchedule else { return }
        let now = Date()
        let oldEnd = step.computedEndTime
        let delta = now.timeIntervalSince(oldEnd)
        guard delta < 0 else { return }

        step.stepStatus = .done
        step.actualEndTime = now
        step.computedEndTime = now
        step.computedDurationMinutes = now.timeIntervalSince(step.computedStartTime) / 60

        cascade(afterEnd: oldEnd, delta: delta, in: schedule)
        promoteNextUpcoming(in: schedule)
        syncLiveActivity()
    }

    func delayStep(_ step: ScheduleStep, byMinutes minutes: Double, modelContext _: ModelContext) {
        guard let schedule = activeSchedule else { return }
        guard minutes > 0 else { return }
        let delta = minutes * 60
        let oldStart = step.computedStartTime

        step.computedStartTime = step.computedStartTime.addingTimeInterval(delta)
        step.computedEndTime = step.computedEndTime.addingTimeInterval(delta)

        cascade(afterEnd: oldStart, delta: delta, in: schedule, excluding: step)
        syncLiveActivity()
    }

    func startStepNow(_ step: ScheduleStep, modelContext _: ModelContext) {
        guard let schedule = activeSchedule else { return }
        let now = Date()
        let delta = now.timeIntervalSince(step.computedStartTime)
        let oldStart = step.computedStartTime
        guard delta > 0 else { return }

        step.computedStartTime = now
        step.computedEndTime = step.computedEndTime.addingTimeInterval(delta)
        step.stepStatus = .active

        for candidate in allSteps(in: schedule)
            where candidate !== step && candidate.stepStatus == .active
        {
            candidate.stepStatus = .upcoming
        }

        cascade(afterEnd: oldStart, delta: delta, in: schedule, excluding: step)
        syncLiveActivity()
    }

    func startStepAt(_ step: ScheduleStep, at startTime: Date, modelContext _: ModelContext) {
        guard let schedule = activeSchedule else { return }
        let delta = startTime.timeIntervalSince(step.computedStartTime)
        let oldStart = step.computedStartTime
        guard abs(delta) > 1 else { return }

        step.computedStartTime = startTime
        step.computedEndTime = step.computedEndTime.addingTimeInterval(delta)
        step.stepStatus = .active

        for candidate in allSteps(in: schedule)
            where candidate !== step && candidate.stepStatus == .active
        {
            candidate.stepStatus = .upcoming
        }

        cascade(afterEnd: oldStart, delta: delta, in: schedule, excluding: step)
        syncLiveActivity()
    }

    func extendStep(_ step: ScheduleStep, byMinutes minutes: Double, modelContext _: ModelContext) {
        guard let schedule = activeSchedule else { return }
        guard minutes > 0 else { return }
        let delta = minutes * 60
        let oldEnd = step.computedEndTime

        step.computedEndTime = step.computedEndTime.addingTimeInterval(delta)
        step.computedDurationMinutes += minutes

        cascade(afterEnd: oldEnd, delta: delta, in: schedule)
        syncLiveActivity()
    }

    func shortenStep(_ step: ScheduleStep, byMinutes minutes: Double, modelContext _: ModelContext) {
        guard let schedule = activeSchedule else { return }
        guard minutes > 0 else { return }
        let delta = -minutes * 60
        let oldEnd = step.computedEndTime
        let newEnd = step.computedEndTime.addingTimeInterval(delta)
        guard newEnd > step.computedStartTime.addingTimeInterval(60) else { return }

        step.computedEndTime = newEnd
        step.computedDurationMinutes = max(1, step.computedDurationMinutes - minutes)

        cascade(afterEnd: oldEnd, delta: delta, in: schedule)
        syncLiveActivity()
    }

    func skipStep(_ step: ScheduleStep, modelContext _: ModelContext) {
        guard let schedule = activeSchedule else { return }
        let delta = -step.computedDurationMinutes * 60
        let oldEnd = step.computedEndTime

        step.stepStatus = .skipped
        step.computedEndTime = step.computedStartTime
        step.computedDurationMinutes = 0

        cascade(afterEnd: oldEnd, delta: delta, in: schedule)
        promoteNextUpcoming(in: schedule)
        syncLiveActivity()
    }

    // MARK: - Finish / Cancel bake

    func finishBake(modelContext: ModelContext) {
        endBake(modelContext: modelContext)
    }

    func cancelBake(modelContext: ModelContext) {
        guard let schedule = activeSchedule else { return }
        let steps = allSteps(in: schedule)
        NotificationService.shared.cancelNotifications(for: steps)
        activeSchedule = nil
        activeConflicts = []
        modelContext.delete(schedule)
        LiveActivityService.shared.endBakeActivity()
    }

    private func endBake(modelContext _: ModelContext) {
        guard let schedule = activeSchedule else { return }
        let steps = allSteps(in: schedule)
        NotificationService.shared.cancelNotifications(for: steps)
        schedule.scheduleStatus = .complete
        activeSchedule = nil
        activeConflicts = []
        LiveActivityService.shared.endBakeActivity()
    }

    // MARK: - Cascade helper

    /// Shifts every step that starts at or after `boundaryEnd` by `delta` seconds, updates the
    /// target bread-ready time, and reschedules notifications. Optionally excludes a step that
    /// has already been shifted inline (e.g. the step whose start time was set to now).
    private func cascade(
        afterEnd boundaryEnd: Date,
        delta: TimeInterval,
        in schedule: Schedule,
        excluding excluded: ScheduleStep? = nil
    ) {
        guard delta != 0 else { return }
        let steps = allSteps(in: schedule)
        for step in steps {
            if step === excluded { continue }
            if step.computedStartTime >= boundaryEnd {
                step.computedStartTime = step.computedStartTime.addingTimeInterval(delta)
                step.computedEndTime = step.computedEndTime.addingTimeInterval(delta)
            }
        }
        schedule.targetBreadReadyTime = schedule.targetBreadReadyTime.addingTimeInterval(delta)

        Task { await NotificationService.shared.rescheduleNotifications(for: steps) }
        validateConflicts(in: schedule)
    }

    private func validateConflicts(in schedule: Schedule) {
        guard let context = schedule.modelContext else {
            activeConflicts = []
            return
        }

        let availability: UserAvailability?
        let windows: [UnavailableWindow]
        do {
            availability = try context.fetch(FetchDescriptor<UserAvailability>()).first
            windows = try context.fetch(FetchDescriptor<UnavailableWindow>())
        } catch {
            activeConflicts = []
            return
        }

        let avail = availability.map { AvailabilityInput(from: $0) }
            ?? AvailabilityInput(startHour: 6, startMinute: 30, endHour: 21, endMinute: 0)
        let windowInputs = windows.map { WindowInput(from: $0) }

        let upcomingHandsOn = orderedTopLevelSteps(in: schedule).filter {
            $0.stepStatus == .upcoming && $0.stepType.classification == .handsOn
        }

        guard !upcomingHandsOn.isEmpty else {
            activeConflicts = []
            return
        }

        let earliest = upcomingHandsOn.first!.computedStartTime
        let latest = upcomingHandsOn.last!.computedEndTime
        let blocks = AvailabilityResolver.resolve(
            from: earliest,
            to: latest,
            availability: avail,
            windows: windowInputs
        )

        var conflicts: [ActiveConflict] = []
        for step in upcomingHandsOn {
            let overlaps = AvailabilityResolver.overlaps(
                start: step.computedStartTime,
                end: step.computedEndTime,
                blocks: blocks
            )
            if !overlaps.isEmpty {
                conflicts.append(ActiveConflict(
                    stepLabel: step.stepType.label,
                    stepSequenceIndex: step.sequenceIndex,
                    scheduledStart: step.computedStartTime,
                    scheduledEnd: step.computedEndTime
                ))
            }
        }
        activeConflicts = conflicts
    }

    /// Marks the earliest still-upcoming step active. Leaves hands-on steps alone —
    /// they're only promoted via `advanceIfReady` once their start time arrives.
    private func promoteNextUpcoming(in schedule: Schedule) {
        let steps = orderedTopLevelSteps(in: schedule)
        guard !steps.contains(where: { $0.stepStatus == .active }) else { return }
        if let next = steps.first(where: { $0.stepStatus == .upcoming }) {
            next.stepStatus = .active
        }
    }

    private func orderedTopLevelSteps(in schedule: Schedule) -> [ScheduleStep] {
        schedule.steps
            .filter { $0.parentStep == nil }
            .sorted { $0.sequenceIndex < $1.sequenceIndex }
    }

    private func allSteps(in schedule: Schedule) -> [ScheduleStep] {
        schedule.steps.sorted { $0.sequenceIndex < $1.sequenceIndex }
    }

    // MARK: - Live Activity

    private func syncLiveActivity() {
        guard let schedule = activeSchedule, schedule.scheduleStatus == .active else {
            LiveActivityService.shared.endBakeActivityImmediately()
            return
        }

        let steps = orderedTopLevelSteps(in: schedule)
        let activeStep = steps.first { $0.stepStatus == .active }
        let isColdRetard = activeStep.flatMap { StepTypeID(rawValue: $0.stepTypeID) } == .coldRetard

        if isColdRetard {
            LiveActivityService.shared.endBakeActivity()
            return
        }

        let state = LiveActivityService.buildBakeState(from: schedule)
        if LiveActivityService.shared.hasBakeActivity {
            LiveActivityService.shared.updateBakeActivity(state: state)
        } else {
            LiveActivityService.shared.startBakeActivity(
                recipeName: schedule.recipe.name,
                recipeID: schedule.recipeID,
                state: state
            )
        }
    }
}

/// Lightweight identifier for deep-linking into a specific step's detail sheet from a notification tap.
struct PendingStepDetail: Identifiable, Equatable {
    let stepTypeID: String
    let sequenceIndex: Int
    var id: String {
        "\(stepTypeID)-\(sequenceIndex)"
    }
}
