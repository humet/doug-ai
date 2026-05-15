import Foundation
import Observation
import SwiftData

enum PreBakeCheckResult {
    case ready
    case needsActivation
    case activating(lastFeed: Date?, peaked: Bool)
    case blocked(StarterHealthStatus)
}

struct ActiveConflict: Identifiable {
    let id = UUID()
    let stepLabel: String
    let stepSequenceIndex: Int
    let scheduledStart: Date
    let scheduledEnd: Date
}

struct ScheduleAdjustment: Identifiable {
    let id = UUID()
    let deltaMinutes: Double
    let newBulkEndTime: Date
}

// MARK: - Time Slot Types

enum SlotViability {
    case available
    case flexed([ScheduleBuilder.FlexCompressionDetail])
    case conflict(ScheduleConflict)
}

struct TimeSlot: Identifiable {
    let id: Date
    let time: Date
    let viability: SlotViability
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
    var viableBreadReadyRange: ClosedRange<Date>?

    var activeSchedule: Schedule?
    var activeConflicts: [ActiveConflict] = []

    // UI state
    var showConflictSheet = false
    var showFlexStepSlider = false
    var showTemperatureEntry = false
    var showRecipeDetailSheet = false
    var selectedFoldStep: ScheduleStep?
    var starterHealthBlock: StarterHealthStatus?
    var pendingFoldEntry: PendingFoldEntry?
    var pendingStepDetail: PendingStepDetail?
    var bulkFermentTargetReached = false
    var lastScheduleAdjustment: ScheduleAdjustment?

    // Levain-in-progress detection
    var detectedLevain: LevainContext?
    var useActiveLevain = false

    // Time slot scanning
    var timeSlots: [TimeSlot] = []
    var disabledWindowIDs: Set<PersistentIdentifier> = []

    init() {
        NotificationRouter.shared.registerScheduleViewModel(self)
        NotificationCenter.default.addObserver(
            forName: StarterViewModel.peakMarkedNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.advancePeakStepIfActive()
            }
        }
    }

    var selectedRecipe: Recipe {
        RecipeBook.recipe(for: selectedRecipeID)
    }

    var currentFlexCompressions: [String: ScheduleBuilder.FlexCompressionDetail] {
        let details = ScheduleBuilder.flexCompressionDetails(steps: previewSteps, recipe: selectedRecipe)
        return Dictionary(uniqueKeysWithValues: details.map { ($0.stepLabel, $0) })
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

    var hasActivationPreamble = false

    func buildPreview(
        availability: UserAvailability?,
        windows: [UnavailableWindow],
        feedLogs: [StarterFeedLog] = [],
        starterProfile: StarterProfile? = nil
    ) {
        let avail = availability.map { AvailabilityInput(from: $0) }
            ?? AvailabilityInput(startHour: 6, startMinute: 30, endHour: 21, endMinute: 0)

        let windowInputs = windows
            .filter { !disabledWindowIDs.contains($0.persistentModelID) }
            .map { WindowInput(from: $0) }
        let peakProfile = feedLogs.isEmpty
            ? nil
            : StarterPeakProfile(feedLogs: feedLogs.map { FeedLogInput(from: $0) }, intentFilter: .activation)

        detectActiveLevain(feedLogs: feedLogs, peakProfile: peakProfile)

        let starterState = starterProfile?.starterLifecycleState ?? .dormant
        if detectedLevain == nil, (starterState == .activating || starterState == .active) {
            detectActivationAsLevain(feedLogs: feedLogs, peakProfile: peakProfile)
        }

        print("[starter] state=\(starterState.rawValue) storage=\(starterProfile?.starterStorageType.rawValue ?? "nil") health=\(starterProfile?.starterHealthStatus.rawValue ?? "nil")")
        if let feed = feedLogs.first {
            let ago = Date().timeIntervalSince(feed.timestamp) / 60
            print("[starter] latestFeed: \(feed.starterFeedIntent.rawValue) \(feed.ratioStarter):\(feed.ratioFlour):\(feed.ratioWater) \(Int(ago))min ago peaked=\(feed.peakTimestamp != nil)")
        }
        if let ctx = detectedLevain {
            print("[starter] levainContext: fedAt=\(ctx.fedAt) elapsed=\(Int(ctx.elapsedMinutes()))min remaining=\(Int(ctx.remainingMinutes()))min expected=\(Int(ctx.expectedPeakMinutes))min")
        } else {
            print("[starter] levainContext: none")
        }

        let earliestStart = computeEarliestStartTime(
            starterProfile: starterProfile,
            feedLogs: feedLogs,
            peakProfile: peakProfile
        )

        viableBreadReadyRange = ScheduleBuilder.viableRange(
            recipe: selectedRecipe,
            kitchenTemperatureCelsius: kitchenTemperature,
            availability: avail,
            windows: windowInputs,
            earliestStartTime: earliestStart,
            peakProfile: peakProfile
        )

        let input = ScheduleBuilderInput(
            recipe: selectedRecipe,
            targetBreadReadyTime: targetDate,
            kitchenTemperatureCelsius: kitchenTemperature,
            availability: avail,
            unavailableWindows: windowInputs,
            peakProfile: peakProfile,
            levainContext: (useActiveLevain || starterState == .activating || starterState == .active) ? detectedLevain : nil,
            earliestStartTime: earliestStart
        )

        print("[buildPreview] recipe=\(selectedRecipe.name) target=\(targetDate) temp=\(kitchenTemperature)°C")
        print("[buildPreview] starterState=\(starterProfile?.starterLifecycleState.rawValue ?? "nil") earliestStart=\(earliestStart)")
        print("[buildPreview] viableRange=\(viableBreadReadyRange.map { "\($0.lowerBound) ... \($0.upperBound)" } ?? "nil")")

        let result = ScheduleBuilder.build(input)

        switch result {
        case let .success(steps):
            print("[buildPreview] builder SUCCESS — \(steps.count) steps")
            if let first = steps.first {
                print("[buildPreview]   firstStep=\(first.label) start=\(first.startTime)")
            }
            if let last = steps.last {
                print("[buildPreview]   lastStep=\(last.label) end=\(last.endTime)")
            }

            let state = starterProfile?.starterLifecycleState ?? .dormant
            let preamble = buildActivationPreamble(
                state: state,
                recipeSteps: steps,
                kitchenTemp: kitchenTemperature,
                feedLogs: feedLogs,
                peakProfile: peakProfile,
                starterProfile: starterProfile,
                availability: avail,
                unavailableBlocks: AvailabilityResolver.resolve(
                    from: (steps.first?.startTime ?? targetDate).addingTimeInterval(-3 * 24 * 3600),
                    to: targetDate,
                    availability: avail,
                    windows: windowInputs
                )
            )
            hasActivationPreamble = !preamble.isEmpty
            print("[buildPreview] preamble=\(preamble.count) steps, hasActivationPreamble=\(hasActivationPreamble)")
            for p in preamble {
                print("[buildPreview]   preamble: \(p.label) start=\(p.startTime) end=\(p.endTime)")
            }

            var shiftedSteps = steps
            if let preambleEnd = preamble.last?.endTime,
               let recipeStart = steps.first?.startTime,
               preambleEnd > recipeStart
            {
                let shift = preambleEnd.timeIntervalSince(recipeStart)
                print("[buildPreview] SHIFTING recipe steps by \(shift / 60)min")
                shiftedSteps = steps.map { step in
                    ScheduledStep(
                        methodStepID: step.methodStepID,
                        stepTypeID: step.stepTypeID,
                        label: step.label,
                        classification: step.classification,
                        startTime: step.startTime.addingTimeInterval(shift),
                        endTime: step.endTime.addingTimeInterval(shift),
                        durationMinutes: step.durationMinutes,
                        subSteps: step.subSteps.map { sub in
                            ScheduledStep(
                                methodStepID: sub.methodStepID,
                                stepTypeID: sub.stepTypeID,
                                label: sub.label,
                                classification: sub.classification,
                                startTime: sub.startTime.addingTimeInterval(shift),
                                endTime: sub.endTime.addingTimeInterval(shift),
                                durationMinutes: sub.durationMinutes,
                                requiresTempReading: sub.requiresTempReading
                            )
                        },
                        requiresTempReading: step.requiresTempReading,
                        levainElapsedMinutes: step.levainElapsedMinutes
                    )
                }
            }

            let allSteps = preamble + shiftedSteps

            let firstActionable = allSteps.first(where: {
                $0.stepTypeID != .fridgeRest && $0.levainElapsedMinutes == nil
            })
            let pastThreshold = Date().addingTimeInterval(-60)
            if let firstStart = firstActionable?.startTime, firstStart < pastThreshold {
                print("[buildPreview] REJECTED — \(firstActionable?.label ?? "") at \(firstStart) before \(pastThreshold)")
                hasActivationPreamble = false
                previewSteps = []
                conflict = ScheduleConflict(
                    conflictingStepLabel: firstActionable?.label ?? "Schedule",
                    conflictingWindowName: "schedule constraint",
                    message: "This bread-ready time requires starting in the past. Pick a later time.",
                    suggestedAlternativeTime: nil
                )
            } else {
                print("[buildPreview] ACCEPTED — \(allSteps.count) steps")
                previewSteps = allSteps
                conflict = nil
            }
        case let .conflict(scheduleConflict):
            print("[buildPreview] builder CONFLICT — \(scheduleConflict.message)")
            hasActivationPreamble = false
            previewSteps = []
            conflict = scheduleConflict
        }
    }

    // MARK: - Time Slot Scanning

    func scanTimeSlots(
        availability: UserAvailability?,
        windows: [UnavailableWindow],
        feedLogs: [StarterFeedLog] = [],
        starterProfile: StarterProfile? = nil
    ) {
        let calendar = Calendar.current
        let avail = availability.map { AvailabilityInput(from: $0) }
            ?? AvailabilityInput(startHour: 6, startMinute: 30, endHour: 21, endMinute: 0)
        let effectiveWindows = windows
            .filter { !disabledWindowIDs.contains($0.persistentModelID) }
            .map { WindowInput(from: $0) }
        let peakProfile = feedLogs.isEmpty
            ? nil
            : StarterPeakProfile(feedLogs: feedLogs.map { FeedLogInput(from: $0) }, intentFilter: .activation)
        let earliest = computeEarliestStartTime(
            starterProfile: starterProfile,
            feedLogs: feedLogs,
            peakProfile: peakProfile
        )
        let starterState = starterProfile?.starterLifecycleState ?? .dormant
        let levain = (useActiveLevain || starterState == .activating || starterState == .active) ? detectedLevain : nil

        let selectedDay = calendar.startOfDay(for: targetDate)
        let scanStart = calendar.date(
            bySettingHour: avail.startHour,
            minute: avail.startMinute,
            second: 0,
            of: selectedDay
        ) ?? selectedDay
        let scanEnd = calendar.date(
            bySettingHour: avail.endHour,
            minute: avail.endMinute,
            second: 0,
            of: selectedDay
        ) ?? selectedDay

        let effectiveScanStart: Date
        if let range = viableBreadReadyRange, calendar.isDate(range.lowerBound, inSameDayAs: selectedDay) {
            effectiveScanStart = range.lowerBound
        } else {
            effectiveScanStart = scanStart
        }

        guard effectiveScanStart < scanEnd else {
            timeSlots = []
            return
        }

        var slots: [TimeSlot] = []
        let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: effectiveScanStart)
        let snappedMinute = ((comps.minute ?? 0) / 30) * 30
        var cursor = calendar.date(
            bySettingHour: comps.hour ?? 0,
            minute: snappedMinute,
            second: 0,
            of: effectiveScanStart
        ) ?? effectiveScanStart
        if cursor < effectiveScanStart {
            cursor = cursor.addingTimeInterval(30 * 60)
        }

        while cursor <= scanEnd {
            let input = ScheduleBuilderInput(
                recipe: selectedRecipe,
                targetBreadReadyTime: cursor,
                kitchenTemperatureCelsius: kitchenTemperature,
                availability: avail,
                unavailableWindows: effectiveWindows,
                peakProfile: peakProfile,
                levainContext: levain,
                earliestStartTime: earliest
            )

            let result = ScheduleBuilder.build(input)

            let viability: SlotViability
            switch result {
            case let .success(steps):
                let firstActionable = steps.first { $0.stepTypeID != .fridgeRest && $0.levainElapsedMinutes == nil }
                if let firstStart = firstActionable?.startTime, firstStart < Date().addingTimeInterval(-60) {
                    viability = .conflict(ScheduleConflict(
                        conflictingStepLabel: firstActionable?.label ?? "Schedule",
                        conflictingWindowName: "schedule constraint",
                        message: "This time requires starting in the past."
                    ))
                } else {
                    let details = ScheduleBuilder.flexCompressionDetails(steps: steps, recipe: selectedRecipe)
                    viability = details.isEmpty ? .available : .flexed(details)
                }
            case let .conflict(c):
                viability = .conflict(c)
            }

            slots.append(TimeSlot(id: cursor, time: cursor, viability: viability))
            cursor = cursor.addingTimeInterval(30 * 60)
        }

        timeSlots = slots
    }

    func relevantWindows(
        from windows: [UnavailableWindow],
        availability: UserAvailability?
    ) -> [UnavailableWindow] {
        let calendar = Calendar.current
        let selectedDay = calendar.startOfDay(for: targetDate)
        let scheduleStart = calendar.date(byAdding: .day, value: -2, to: selectedDay) ?? selectedDay
        let scheduleEnd = calendar.date(byAdding: .day, value: 1, to: selectedDay) ?? selectedDay
        let avail = availability.map { AvailabilityInput(from: $0) }
            ?? AvailabilityInput(startHour: 6, startMinute: 30, endHour: 21, endMinute: 0)

        return windows.filter { window in
            guard window.isActive else { return false }
            let blocks = AvailabilityResolver.resolve(
                from: scheduleStart,
                to: scheduleEnd,
                availability: avail,
                windows: [WindowInput(from: window)]
            )
            return blocks.contains { $0.sourceName == window.name }
        }
    }

    func resetOverrides() {
        disabledWindowIDs = []
    }

    private func detectActiveLevain(
        feedLogs: [StarterFeedLog],
        peakProfile: StarterPeakProfile?
    ) {
        guard let latest = feedLogs.first,
              latest.peakTimestamp == nil,
              latest.starterFeedIntent == .levain
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

    private func detectActivationAsLevain(
        feedLogs: [StarterFeedLog],
        peakProfile: StarterPeakProfile?
    ) {
        guard let latest = feedLogs.first,
              latest.peakTimestamp == nil,
              latest.starterFeedIntent == .activation
        else { return }

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
        guard elapsed < expectedPeak * 1.5 else { return }

        detectedLevain = LevainContext(
            fedAt: latest.timestamp,
            expectedPeakMinutes: expectedPeak,
            kitchenTemperatureCelsius: latest.kitchenTemperatureCelsius
        )
        useActiveLevain = true
    }

    // MARK: - Earliest Start Time

    private func computeEarliestStartTime(
        starterProfile: StarterProfile?,
        feedLogs: [StarterFeedLog],
        peakProfile: StarterPeakProfile?
    ) -> Date {
        let now = Date()
        guard let profile = starterProfile else { return now }

        switch profile.starterLifecycleState {
        case .active:
            return now
        case .activating:
            let lastActivation = feedLogs.first(where: { $0.starterFeedIntent == .activation })
            if lastActivation?.peakTimestamp != nil { return now }

            let bracket = TemperatureBracket.bracket(celsius: kitchenTemperature)
            let peakDuration: Double = if let pp = peakProfile,
                                          let observed = pp.averageMinutes(ratio: .oneToFive, tempBracket: bracket)
            {
                observed
            } else {
                profile.activePeakAverageMinutes
                    ?? TemperatureCalculator.levainBuildMinutes(kitchenTemp: kitchenTemperature)
            }

            if let activationTime = lastActivation?.timestamp {
                let peakExpected = activationTime.addingTimeInterval(peakDuration * 60)
                return max(now, peakExpected)
            }
            return now
        case .dormant:
            let activateDuration = 10.0
            let bracket = TemperatureBracket.bracket(celsius: kitchenTemperature)
            let peakDuration: Double = if let pp = peakProfile,
                                          let observed = pp.averageMinutes(ratio: .oneToFive, tempBracket: bracket)
            {
                observed
            } else {
                profile.activePeakAverageMinutes
                    ?? TemperatureCalculator.levainBuildMinutes(kitchenTemp: kitchenTemperature)
            }
            let warmUp = profile.starterStorageType == .fridge
                ? TemperatureCalculator.fridgeWarmUpMinutes(kitchenTempCelsius: kitchenTemperature)
                : 0.0
            return now.addingTimeInterval((activateDuration + peakDuration + warmUp) * 60)
        case .reviving:
            return now.addingTimeInterval(24 * 3600)
        }
    }

    // MARK: - Activation Preamble

    private func buildActivationPreamble(
        state: StarterLifecycleState,
        recipeSteps: [ScheduledStep],
        kitchenTemp: Double,
        feedLogs: [StarterFeedLog],
        peakProfile: StarterPeakProfile?,
        starterProfile: StarterProfile?,
        availability: AvailabilityInput,
        unavailableBlocks: [UnavailableBlock]
    ) -> [ScheduledStep] {
        switch state {
        case .active:
            return []
        case .reviving:
            return []
        case .activating:
            return buildActivatingPreamble(
                feedLogs: feedLogs,
                peakProfile: peakProfile,
                starterProfile: starterProfile,
                kitchenTemp: kitchenTemp,
                recipeSteps: recipeSteps
            )
        case .dormant:
            return buildDormantPreamble(
                recipeSteps: recipeSteps,
                kitchenTemp: kitchenTemp,
                peakProfile: peakProfile,
                starterProfile: starterProfile,
                unavailableBlocks: unavailableBlocks
            )
        }
    }

    private func buildActivatingPreamble(
        feedLogs: [StarterFeedLog],
        peakProfile: StarterPeakProfile?,
        starterProfile: StarterProfile?,
        kitchenTemp: Double,
        recipeSteps: [ScheduledStep]
    ) -> [ScheduledStep] {
        let lastActivation = feedLogs.first(where: { $0.starterFeedIntent == .activation })
        let hasPeaked = lastActivation?.peakTimestamp != nil

        if hasPeaked { return [] }

        let bracket = TemperatureBracket.bracket(celsius: kitchenTemp)
        let peakDuration: Double = if let profile = peakProfile,
                                      let observed = profile.averageMinutes(ratio: .oneToFive, tempBracket: bracket)
        {
            observed
        } else {
            starterProfile?.activePeakAverageMinutes
                ?? TemperatureCalculator.levainBuildMinutes(kitchenTemp: kitchenTemp)
        }

        var remainingPeakMinutes = peakDuration
        if let activationTime = lastActivation?.timestamp {
            let elapsed = Date().timeIntervalSince(activationTime) / 60.0
            remainingPeakMinutes = max(0, peakDuration - elapsed)
        }

        guard remainingPeakMinutes > 0 else { return [] }

        let now = Date()
        let peakStart = now
        let peakEnd = now.addingTimeInterval(remainingPeakMinutes * 60)

        return [ScheduledStep(
            methodStepID: UUID(),
            stepTypeID: .waitForPeak,
            label: "Wait for Peak",
            classification: .passiveFixed,
            startTime: peakStart,
            endTime: peakEnd,
            durationMinutes: remainingPeakMinutes
        )]
    }

    private func buildDormantPreamble(
        recipeSteps: [ScheduledStep],
        kitchenTemp: Double,
        peakProfile: StarterPeakProfile?,
        starterProfile: StarterProfile?,
        unavailableBlocks: [UnavailableBlock]
    ) -> [ScheduledStep] {
        guard let levainStart = recipeSteps.first?.startTime else { return [] }

        let bracket = TemperatureBracket.bracket(celsius: kitchenTemp)
        let peakDuration: Double = if let profile = peakProfile,
                                      let observed = profile.averageMinutes(ratio: .oneToFive, tempBracket: bracket)
        {
            observed
        } else {
            starterProfile?.activePeakAverageMinutes
                ?? TemperatureCalculator.levainBuildMinutes(kitchenTemp: kitchenTemp)
        }

        let activateDuration = 10.0
        var activateStart = levainStart.addingTimeInterval(-(peakDuration + activateDuration) * 60)

        let conflicts = AvailabilityResolver.overlaps(
            start: activateStart,
            end: activateStart.addingTimeInterval(activateDuration * 60),
            blocks: unavailableBlocks
        )
        if let conflict = conflicts.first {
            activateStart = conflict.start.addingTimeInterval(-activateDuration * 60)
        }

        let activateEnd = activateStart.addingTimeInterval(activateDuration * 60)
        let waitForPeakStart = activateEnd
        let waitForPeakEnd = levainStart

        var steps: [ScheduledStep] = []

        let now = Date()
        if activateStart.timeIntervalSince(now) > 30 * 60 {
            steps.append(ScheduledStep(
                methodStepID: UUID(),
                stepTypeID: .fridgeRest,
                label: "Starter Resting",
                classification: .passiveFixed,
                startTime: now,
                endTime: activateStart,
                durationMinutes: activateStart.timeIntervalSince(now) / 60.0
            ))
        }

        steps.append(ScheduledStep(
            methodStepID: UUID(),
            stepTypeID: .activateStarter,
            label: "Activate Starter",
            classification: .handsOn,
            startTime: activateStart,
            endTime: activateEnd,
            durationMinutes: activateDuration
        ))

        let waitDuration = waitForPeakEnd.timeIntervalSince(waitForPeakStart) / 60.0
        if waitDuration > 0 {
            steps.append(ScheduledStep(
                methodStepID: UUID(),
                stepTypeID: .waitForPeak,
                label: "Wait for Peak",
                classification: .passiveFixed,
                startTime: waitForPeakStart,
                endTime: waitForPeakEnd,
                durationMinutes: waitDuration
            ))
        }

        return steps
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

    func preBakeCheck(
        profile: StarterProfile?,
        feedLogs: [StarterFeedLog]
    ) -> PreBakeCheckResult {
        guard let profile else { return .blocked(.needsFeed) }

        switch profile.starterLifecycleState {
        case .active:
            return .ready
        case .activating:
            let lastActivation = feedLogs.first { $0.starterFeedIntent == .activation }
            return .activating(lastFeed: lastActivation?.timestamp, peaked: lastActivation?.peakTimestamp != nil)
        case .reviving:
            return .blocked(.needsRevival)
        case .dormant:
            let profileInput = StarterProfileInput(from: profile)
            let logInputs = feedLogs.map { FeedLogInput(from: $0) }
            let status = StarterHealthAssessor.assess(profile: profileInput, feedLogs: logInputs)
            switch status {
            case .readyToBake:
                return .needsActivation
            case .needsFeed:
                return .needsActivation
            case .needsRevival:
                return .blocked(.needsRevival)
            }
        }
    }

    func preBakeHealthCheck(
        profile: StarterProfile?,
        feedLogs: [StarterFeedLog]
    ) -> Bool {
        let result = preBakeCheck(profile: profile, feedLogs: feedLogs)
        switch result {
        case .ready:
            starterHealthBlock = nil
            return true
        case .needsActivation:
            starterHealthBlock = .needsFeed
            return false
        case .activating:
            starterHealthBlock = .needsFeed
            return false
        case let .blocked(status):
            starterHealthBlock = status
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
        promoteNextUpcoming(in: schedule)

        if let firstActive = orderedTopLevelSteps(in: schedule).first(where: { $0.stepStatus == .active }) {
            let profiles = (try? modelContext.fetch(FetchDescriptor<StarterProfile>())) ?? []
            applyStepSideEffects(
                firstActive, event: .started, feedDetails: nil,
                profile: profiles.first, modelContext: modelContext
            )
        }

        Task {
            await NotificationService.shared.scheduleNotifications(for: persistedSteps)

            if let autolyseStep = persistedSteps.first(where: {
                StepTypeID(rawValue: $0.stepTypeID) == .autolyse
            }) {
                let reminderTime = autolyseStep.computedStartTime.addingTimeInterval(5 * 60)
                await NotificationService.shared.scheduleRefeedReminder(at: reminderTime)
            }
        }
        syncLiveActivity()
    }

    // MARK: - Flexible Step Adjustment

    func adjustFlexibleStep(to newDurationMinutes: Double, modelContext _: ModelContext) {
        guard let schedule = activeSchedule else { return }

        let steps = allSteps(in: schedule)
        guard let flexStep = steps.first(where: { step in
            guard let id = StepTypeID(rawValue: step.stepTypeID) else { return false }
            return StepTypeRegistry.type(for: id).classification == .passiveFlexible
                && StepTypeRegistry.type(for: id).flexRange != nil
        }) else { return }

        let oldEnd = flexStep.computedEndTime
        let newEnd = flexStep.computedStartTime.addingTimeInterval(newDurationMinutes * 60)
        let delta = newEnd.timeIntervalSince(oldEnd)

        flexStep.computedEndTime = newEnd
        flexStep.computedDurationMinutes = newDurationMinutes

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

        if remainingMinutes < 15 {
            bulkFermentTargetReached = true
            return
        }

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

        lastScheduleAdjustment = ScheduleAdjustment(
            deltaMinutes: delta / 60.0,
            newBulkEndTime: newBulkEnd
        )
    }

    // MARK: - Flexible Step Lookup

    var flexibleStep: ScheduleStep? {
        activeSchedule?.steps.first(where: { step in
            guard let id = StepTypeID(rawValue: step.stepTypeID) else { return false }
            let stepType = StepTypeRegistry.type(for: id)
            return stepType.classification == .passiveFlexible && stepType.flexRange != nil
        })
    }

    var flexibleStepFlexRange: ClosedRange<Double>? {
        guard let step = flexibleStep,
              let id = StepTypeID(rawValue: step.stepTypeID)
        else { return nil }
        let recipe = activeSchedule.map { RecipeBook.recipe(for: RecipeID(rawValue: $0.recipeID)!) }
        let methodStep = recipe?.method.first(where: { $0.stepTypeID == id })
        return methodStep?.effectiveFlexRange
    }

    var remainingMinutesAfterFlexStep: Double {
        guard let schedule = activeSchedule,
              let flexStep = flexibleStep
        else { return 0 }
        let steps = allSteps(in: schedule)
        let flexEnd = flexStep.computedEndTime
        return steps
            .filter { $0.computedStartTime >= flexEnd }
            .reduce(0.0) { $0 + $1.computedDurationMinutes }
    }

    // MARK: - Per-step adjustment controls

    func markStepDone(_ step: ScheduleStep, modelContext: ModelContext) {
        markStepDone(step, feedDetails: nil, starterProfile: nil, modelContext: modelContext)
    }

    func markStepDone(
        _ step: ScheduleStep,
        feedDetails: FeedDetails?,
        starterProfile: StarterProfile?,
        modelContext: ModelContext
    ) {
        guard let schedule = activeSchedule else { return }
        NotificationService.shared.cancelNotifications(for: [step])
        step.stepStatus = .done
        if step.actualEndTime == nil {
            step.actualEndTime = Date()
        }
        if let actual = step.actualEndTime {
            let delta = actual.timeIntervalSince(step.computedEndTime)
            if delta > 0 {
                cascade(afterEnd: step.computedEndTime, delta: delta, in: schedule, excluding: step)
            }
        }

        if let parent = step.parentStep {
            let lastSubEnd = parent.subSteps.map(\.computedEndTime).max()
            if let end = lastSubEnd, end > parent.computedEndTime {
                parent.computedEndTime = end
            }
        }

        applyStepSideEffects(
            step, event: .completed, feedDetails: feedDetails,
            profile: starterProfile, modelContext: modelContext
        )

        promoteNextUpcoming(in: schedule)

        if let next = nextStep(after: step, in: schedule) {
            applyStepSideEffects(
                next, event: .started, feedDetails: nil,
                profile: starterProfile, modelContext: modelContext
            )
        }

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

        step.stepStatus = .active
        step.actualEndTime = nil

        syncLiveActivity()
    }

    private func rescheduleSubSteps(of step: ScheduleStep) {
        let subs = step.subSteps.sorted { $0.sequenceIndex < $1.sequenceIndex }
        guard !subs.isEmpty else { return }

        let remaining = step.computedEndTime.timeIntervalSince(step.computedStartTime)
        let pendingFolds = subs.filter { $0.stepStatus != .done }
        guard !pendingFolds.isEmpty else { return }

        let spacingFraction = 0.67
        let foldWindow = remaining * spacingFraction
        let spacing = foldWindow / Double(pendingFolds.count + 1)

        for (index, sub) in pendingFolds.enumerated() {
            let offset = spacing * Double(index + 1)
            sub.computedStartTime = step.computedStartTime.addingTimeInterval(offset)
            sub.computedEndTime = sub.computedStartTime.addingTimeInterval(sub.computedDurationMinutes * 60)
            sub.stepStatus = .upcoming
            sub.actualEndTime = nil
        }
        Task { await NotificationService.shared.rescheduleNotifications(for: pendingFolds) }
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
                if didChange || !steps.contains(where: { $0.stepStatus == .active }) {
                    promoteNextUpcoming(in: schedule)
                    syncLiveActivity()
                }
                advanceSubSteps(in: schedule, now: now)
                return
            case .active:
                if step.stepType.classification == .passiveFixed, step.computedEndTime <= now {
                    if step.stepTypeID == StepTypeID.bake.rawValue,
                       !step.subSteps.allSatisfy({ $0.stepStatus == .done || $0.stepStatus == .skipped })
                    {
                        advanceSubSteps(in: schedule, now: now)
                        return
                    }
                    let manualSteps: Set<String> = [
                        StepTypeID.buildLevain.rawValue,
                        StepTypeID.waitForPeak.rawValue,
                        StepTypeID.bulkFerment.rawValue,
                        StepTypeID.preheat.rawValue,
                        StepTypeID.bakeSheet.rawValue,
                    ]
                    if manualSteps.contains(step.stepTypeID) {
                        advanceSubSteps(in: schedule, now: now)
                        return
                    }
                    NotificationService.shared.cancelNotifications(for: [step])
                    step.stepStatus = .done
                    step.actualEndTime = step.subSteps.isEmpty ? step.computedEndTime : now
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

        if active.stepTypeID == StepTypeID.bake.rawValue {
            for sub in subs {
                switch sub.stepStatus {
                case .done, .skipped: continue
                case .active: return
                case .upcoming:
                    if !subs.contains(where: { $0.stepStatus == .active }) {
                        sub.stepStatus = .active
                    }
                    return
                }
            }
            return
        }

        let spacing: TimeInterval = subs.count >= 2
            ? subs[1].computedStartTime.timeIntervalSince(subs[0].computedStartTime)
            : 30 * 60
        let minimumGap = max(spacing / 2, 15 * 60)

        for (index, sub) in subs.enumerated() {
            switch sub.stepStatus {
            case .done, .skipped:
                continue
            case .active, .upcoming:
                let tooLate: Bool = if index + 1 < subs.count {
                    subs[index + 1].computedStartTime <= now
                } else {
                    now.timeIntervalSince(sub.computedStartTime) > spacing
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
                       now.timeIntervalSince(doneTime) < minimumGap
                    {
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

    func startStepNow(
        _ step: ScheduleStep,
        starterProfile: StarterProfile? = nil,
        modelContext: ModelContext
    ) {
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

        applyStepSideEffects(
            step, event: .started, feedDetails: nil,
            profile: starterProfile, modelContext: modelContext
        )

        NotificationService.shared.cancelNotifications(for: [step])
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

    // MARK: - Peak Sync from Starter Tab

    private func advancePeakStepIfActive() {
        guard let schedule = activeSchedule else { return }
        let steps = orderedTopLevelSteps(in: schedule)
        guard let active = steps.first(where: { $0.stepStatus == .active }) else { return }

        let stepID = StepTypeID(rawValue: active.stepTypeID)
        guard stepID == .buildLevain || stepID == .waitForPeak else { return }

        guard let context = schedule.modelContext else { return }
        let profiles = (try? context.fetch(FetchDescriptor<StarterProfile>())) ?? []

        markStepDone(
            active,
            feedDetails: nil,
            starterProfile: profiles.first,
            modelContext: context
        )
    }

    // MARK: - Bake Coordinator Side Effects

    private func applyStepSideEffects(
        _ step: ScheduleStep,
        event: StepEvent,
        feedDetails: FeedDetails?,
        profile: StarterProfile?,
        modelContext: ModelContext
    ) {
        guard let profile,
              let stepTypeID = StepTypeID(rawValue: step.stepTypeID)
        else { return }

        let effects = BakeCoordinator.sideEffects(
            forStep: stepTypeID,
            event: event,
            starterState: profile.starterLifecycleState,
            feedDetails: feedDetails,
            kitchenTempCelsius: activeSchedule?.kitchenTemperatureCelsius ?? 22
        )

        for effect in effects {
            switch effect {
            case let .transitionLifecycle(result):
                profile.starterLifecycleState = result.newState
            case let .logFeed(input):
                let log = StarterFeedLog(
                    timestamp: input.timestamp,
                    ratioStarter: input.ratioStarter,
                    ratioFlour: input.ratioFlour,
                    ratioWater: input.ratioWater,
                    flourType: input.flourType,
                    kitchenTemperatureCelsius: input.kitchenTemperatureCelsius,
                    feedIntent: input.feedIntent
                )
                modelContext.insert(log)
            case let .markPeakOnLatestFeed(intent):
                let descriptor = FetchDescriptor<StarterFeedLog>(
                    sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
                )
                if let logs = try? modelContext.fetch(descriptor) {
                    let target = logs.first(where: { $0.starterFeedIntent == intent && $0.peakTimestamp == nil })
                        ?? logs.first(where: { $0.starterFeedIntent == .activation && $0.peakTimestamp == nil })
                    if let feed = target {
                        feed.markPeak(at: Date())
                        if let avg = profile.activePeakAverageMinutes, let peak = feed.timeToPeakMinutes {
                            profile.activePeakAverageMinutes = (avg + peak) / 2.0
                        } else if let peak = feed.timeToPeakMinutes {
                            profile.activePeakAverageMinutes = peak
                        }
                    }
                }
            case let .updateStorageType(type):
                profile.starterStorageType = type
            }
        }
    }

    private func nextStep(after step: ScheduleStep, in schedule: Schedule) -> ScheduleStep? {
        let steps = orderedTopLevelSteps(in: schedule)
        guard let idx = steps.firstIndex(where: { $0 === step }),
              idx + 1 < steps.count
        else { return nil }
        let next = steps[idx + 1]
        return next.stepStatus == .active ? next : nil
    }

    // MARK: - Switch Recipe

    func switchRecipe(
        to recipeID: RecipeID,
        availability: UserAvailability?,
        windows: [UnavailableWindow],
        feedLogs: [StarterFeedLog],
        starterProfile: StarterProfile?,
        modelContext: ModelContext
    ) {
        cancelBake(modelContext: modelContext)
        selectedRecipeID = recipeID

        detectActiveLevain(
            feedLogs: feedLogs,
            peakProfile: feedLogs.isEmpty
                ? nil
                : StarterPeakProfile(feedLogs: feedLogs.map { FeedLogInput(from: $0) })
        )
        if detectedLevain != nil {
            useActiveLevain = true
        }

        buildPreview(
            availability: availability,
            windows: Array(windows),
            feedLogs: Array(feedLogs),
            starterProfile: starterProfile
        )
    }

    // MARK: - Finish / Cancel bake

    func finishBake(modelContext: ModelContext) {
        endBake(modelContext: modelContext)
    }

    func cancelBake(modelContext: ModelContext) {
        guard let schedule = activeSchedule else { return }
        let steps = allSteps(in: schedule)
        NotificationService.shared.cancelNotifications(for: steps)
        NotificationService.shared.cancelRefeedReminder()
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
            $0.stepStatus == .upcoming && (
                $0.stepType.classification == .handsOn || $0.stepType.requiresPresence
            )
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

    private var lastPromotedStepTypeID: String?

    private func promoteNextUpcoming(in schedule: Schedule) {
        let steps = orderedTopLevelSteps(in: schedule)
        guard !steps.contains(where: { $0.stepStatus == .active }) else { return }
        if let next = steps.first(where: { $0.stepStatus == .upcoming }) {
            next.stepStatus = .active
            lastPromotedStepTypeID = next.stepTypeID
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
            LiveActivityService.shared.endBakeActivity()
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
