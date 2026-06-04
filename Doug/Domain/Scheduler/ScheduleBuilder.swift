import Foundation

// MARK: - Input / Output Types

struct ScheduleBuilderInput {
    let recipe: Recipe
    let targetBreadReadyTime: Date
    let kitchenTemperatureCelsius: Double
    let availability: AvailabilityInput
    let unavailableWindows: [WindowInput]
    let calendar: Calendar
    let peakProfile: StarterPeakProfile?
    let levainContext: LevainContext?
    let earliestStartTime: Date?

    init(
        recipe: Recipe,
        targetBreadReadyTime: Date,
        kitchenTemperatureCelsius: Double,
        availability: AvailabilityInput,
        unavailableWindows: [WindowInput] = [],
        calendar: Calendar = .current,
        peakProfile: StarterPeakProfile? = nil,
        levainContext: LevainContext? = nil,
        earliestStartTime: Date? = nil
    ) {
        self.recipe = recipe
        self.targetBreadReadyTime = targetBreadReadyTime
        self.kitchenTemperatureCelsius = kitchenTemperatureCelsius
        self.availability = availability
        self.unavailableWindows = unavailableWindows
        self.calendar = calendar
        self.peakProfile = peakProfile
        self.levainContext = levainContext
        self.earliestStartTime = earliestStartTime
    }
}

/// A single step in the generated schedule.
struct ScheduledStep: Identifiable {
    let id: UUID
    let methodStepID: UUID
    let stepTypeID: StepTypeID
    let label: String
    let classification: StepClassification
    let startTime: Date
    let endTime: Date
    let durationMinutes: Double
    let subSteps: [ScheduledStep]
    let requiresTempReading: Bool
    let levainElapsedMinutes: Double?

    init(
        methodStepID: UUID,
        stepTypeID: StepTypeID,
        label: String,
        classification: StepClassification,
        startTime: Date,
        endTime: Date,
        durationMinutes: Double,
        subSteps: [ScheduledStep] = [],
        requiresTempReading: Bool = false,
        levainElapsedMinutes: Double? = nil
    ) {
        id = UUID()
        self.methodStepID = methodStepID
        self.stepTypeID = stepTypeID
        self.label = label
        self.classification = classification
        self.startTime = startTime
        self.endTime = endTime
        self.durationMinutes = durationMinutes
        self.subSteps = subSteps
        self.requiresTempReading = requiresTempReading
        self.levainElapsedMinutes = levainElapsedMinutes
    }
}

enum ScheduleResult {
    case success([ScheduledStep])
    case conflict(ScheduleConflict)
}

struct ScheduleConflict {
    let conflictingStepLabel: String
    let conflictingWindowName: String
    let conflictingWindowStart: Date?
    let conflictingWindowEnd: Date?
    let message: String
    let suggestedAlternativeTime: Date?

    init(
        conflictingStepLabel: String,
        conflictingWindowName: String,
        conflictingWindowStart: Date? = nil,
        conflictingWindowEnd: Date? = nil,
        message: String,
        suggestedAlternativeTime: Date? = nil
    ) {
        self.conflictingStepLabel = conflictingStepLabel
        self.conflictingWindowName = conflictingWindowName
        self.conflictingWindowStart = conflictingWindowStart
        self.conflictingWindowEnd = conflictingWindowEnd
        self.message = message
        self.suggestedAlternativeTime = suggestedAlternativeTime
    }
}

// MARK: - Schedule Builder

enum ScheduleBuilder {
    /// Builds a schedule by working backwards from the target bread-ready time.
    ///
    /// Iterates the recipe's method in reverse, subtracting durations and
    /// checking hands-on steps against availability constraints.
    static func build(_ input: ScheduleBuilderInput) -> ScheduleResult {
        let calendar = input.calendar

        // Resolve availability into concrete unavailable blocks
        // We need blocks spanning a generous window (3 days before target)
        let rangeStart = calendar.date(byAdding: .day, value: -3, to: input.targetBreadReadyTime)
            ?? input.targetBreadReadyTime
        let unavailableBlocks = AvailabilityResolver.resolve(
            from: rangeStart,
            to: input.targetBreadReadyTime,
            availability: input.availability,
            windows: input.unavailableWindows,
            calendar: calendar
        )

        var cursor = input.targetBreadReadyTime
        var scheduledSteps: [ScheduledStep] = []
        var pendingPresenceGap: TimeInterval = 0

        // Iterate method steps in REVERSE order (backward from target time)
        let method = input.recipe.method
        let reversedMethod = Array(method.reversed())
        for (reversedIndex, methodStep) in reversedMethod.enumerated() {
            let stepType = methodStep.stepType

            var duration = TemperatureCalculator.effectiveDuration(
                for: methodStep,
                kitchenTemp: input.kitchenTemperatureCelsius,
                peakProfile: input.peakProfile
            )

            var levainElapsed: Double?
            if methodStep.stepTypeID == .waitForLevainPeak, let ctx = input.levainContext {
                let remaining = ctx.remainingMinutes()
                levainElapsed = ctx.elapsedMinutes()
                duration = remaining > 0 ? remaining : 10
            }

            var tentativeEnd = cursor
            var tentativeStart = calendar.date(
                byAdding: .minute,
                value: -Int(duration),
                to: tentativeEnd
            ) ?? tentativeEnd

            switch stepType.classification {
            case .passiveFixed, .passiveFlexible:
                // Check interaction points for steps that require user presence
                if stepType.requiresPresence {
                    let (moments, groupDuration) = presenceGroupInteractionMoments(
                        from: reversedIndex,
                        in: reversedMethod,
                        groupEnd: tentativeEnd,
                        kitchenTemp: input.kitchenTemperatureCelsius,
                        peakProfile: input.peakProfile,
                        calendar: calendar
                    )

                    let conflictingMoment = moments.last { moment in
                        !AvailabilityResolver.momentOverlaps(moment, blocks: unavailableBlocks).isEmpty
                    }

                    if let conflictingMoment {
                        let block = AvailabilityResolver.momentOverlaps(
                            conflictingMoment, blocks: unavailableBlocks
                        ).first!

                        let shiftAmount = conflictingMoment.timeIntervalSince(block.start) + 60
                        let shiftedEnd = tentativeEnd.addingTimeInterval(-shiftAmount)
                        let shiftedStart = calendar.date(
                            byAdding: .minute, value: -Int(duration), to: shiftedEnd
                        ) ?? shiftedEnd

                        let shiftedMoments = moments.map { $0.addingTimeInterval(-shiftAmount) }
                        let stillConflicting = shiftedMoments.contains { moment in
                            !AvailabilityResolver.momentOverlaps(moment, blocks: unavailableBlocks).isEmpty
                        }

                        if stillConflicting {
                            let conflictBlock = shiftedMoments.lazy.compactMap { moment in
                                AvailabilityResolver.momentOverlaps(moment, blocks: unavailableBlocks).first
                            }.first
                            return .conflict(ScheduleConflict(
                                conflictingStepLabel: stepType.label,
                                conflictingWindowName: conflictBlock?.sourceName ?? "your available hours",
                                conflictingWindowStart: conflictBlock?.start,
                                conflictingWindowEnd: conflictBlock?.end,
                                message: "\(stepType.label) conflicts with \(conflictBlock?.sourceName ?? "your available hours") and cannot be rescheduled. Try a different bread-ready time.",
                                suggestedAlternativeTime: nil
                            ))
                        }

                        pendingPresenceGap = shiftAmount
                        tentativeEnd = shiftedEnd
                        tentativeStart = shiftedStart
                    }
                }

                if stepType.classification == .passiveFlexible, pendingPresenceGap > 0 {
                    duration += pendingPresenceGap / 60
                    tentativeStart = calendar.date(
                        byAdding: .minute, value: -Int(duration), to: tentativeEnd
                    ) ?? tentativeEnd
                    pendingPresenceGap = 0
                }

                // Passive steps can run through unavailable windows
                var step = ScheduledStep(
                    methodStepID: methodStep.id,
                    stepTypeID: methodStep.stepTypeID,
                    label: stepType.label,
                    classification: stepType.classification,
                    startTime: tentativeStart,
                    endTime: tentativeEnd,
                    durationMinutes: duration,
                    requiresTempReading: stepType.requiresTempReading,
                    levainElapsedMinutes: levainElapsed
                )

                // Sub-schedule folds within bulk ferment
                if methodStep.stepTypeID == .bulkFerment, let foldCount = methodStep.foldCount {
                    let spacingFraction = methodStep.foldSpacingFraction ?? 0.67
                    var bulkStart = tentativeStart
                    var bulkEnd = tentativeEnd

                    let foldWindowEnd = bulkStart.addingTimeInterval(duration * spacingFraction * 60)
                    let foldConflicts = AvailabilityResolver.overlaps(
                        start: bulkStart,
                        end: foldWindowEnd,
                        blocks: unavailableBlocks
                    )

                    if let conflict = foldConflicts.first {
                        let newBulkStart = conflict.start.addingTimeInterval(-duration * spacingFraction * 60)
                        let newBulkEnd = newBulkStart.addingTimeInterval(duration * 60)
                        let delta = tentativeEnd.timeIntervalSince(newBulkEnd)

                        if let resolution = repositionForFoldAvailability(
                            delta: delta,
                            scheduledSteps: &scheduledSteps,
                            unavailableBlocks: unavailableBlocks,
                            method: method,
                            calendar: calendar
                        ) {
                            return resolution
                        }

                        bulkStart = newBulkStart
                        bulkEnd = newBulkEnd
                        step = ScheduledStep(
                            methodStepID: methodStep.id,
                            stepTypeID: methodStep.stepTypeID,
                            label: stepType.label,
                            classification: stepType.classification,
                            startTime: bulkStart,
                            endTime: bulkEnd,
                            durationMinutes: duration,
                            requiresTempReading: stepType.requiresTempReading,
                            levainElapsedMinutes: levainElapsed
                        )
                    }

                    let folds = scheduleFolds(
                        bulkStart: bulkStart,
                        bulkEnd: bulkEnd,
                        foldCount: foldCount,
                        spacingFraction: spacingFraction,
                        inclusionAtFold: methodStep.inclusionAtFold,
                        unavailableBlocks: unavailableBlocks,
                        calendar: calendar
                    )
                    step = ScheduledStep(
                        methodStepID: step.methodStepID,
                        stepTypeID: step.stepTypeID,
                        label: step.label,
                        classification: step.classification,
                        startTime: step.startTime,
                        endTime: step.endTime,
                        durationMinutes: step.durationMinutes,
                        subSteps: folds,
                        requiresTempReading: step.requiresTempReading
                    )
                }

                if !methodStep.subSteps.isEmpty {
                    var subStart = tentativeStart
                    let subs = methodStep.subSteps.map { sub -> ScheduledStep in
                        let subType = StepTypeRegistry.type(for: sub.stepTypeID)
                        let subDuration = sub.effectiveDuration
                        let subEnd = subStart.addingTimeInterval(subDuration * 60)
                        defer { subStart = subEnd }
                        return ScheduledStep(
                            methodStepID: sub.id,
                            stepTypeID: sub.stepTypeID,
                            label: subType.label,
                            classification: subType.classification,
                            startTime: subStart,
                            endTime: subEnd,
                            durationMinutes: subDuration,
                            requiresTempReading: subType.requiresTempReading
                        )
                    }
                    step = ScheduledStep(
                        methodStepID: step.methodStepID,
                        stepTypeID: step.stepTypeID,
                        label: step.label,
                        classification: step.classification,
                        startTime: step.startTime,
                        endTime: step.endTime,
                        durationMinutes: step.durationMinutes,
                        subSteps: subs,
                        requiresTempReading: step.requiresTempReading
                    )
                }

                scheduledSteps.append(step)
                cursor = step.startTime

            case .handsOn:
                let conflicts = AvailabilityResolver.overlaps(
                    start: tentativeStart,
                    end: tentativeEnd,
                    blocks: unavailableBlocks
                )

                if conflicts.isEmpty {
                    // No conflict — place directly
                    scheduledSteps.append(ScheduledStep(
                        methodStepID: methodStep.id,
                        stepTypeID: methodStep.stepTypeID,
                        label: stepType.label,
                        classification: stepType.classification,
                        startTime: tentativeStart,
                        endTime: tentativeEnd,
                        durationMinutes: duration,
                        requiresTempReading: stepType.requiresTempReading
                    ))
                    cursor = tentativeStart
                } else {
                    // Try to resolve by adjusting adjacent flexible steps
                    if let resolution = resolveConflict(
                        step: methodStep,
                        tentativeStart: tentativeStart,
                        tentativeEnd: tentativeEnd,
                        duration: duration,
                        conflicts: conflicts,
                        scheduledSteps: &scheduledSteps,
                        cursor: &cursor,
                        unavailableBlocks: unavailableBlocks,
                        calendar: calendar
                    ) {
                        return resolution
                    }
                    // If resolveConflict returned nil, it successfully placed the step
                    // by mutating scheduledSteps and cursor
                }
            }
        }

        // Reverse to chronological order
        var result: [ScheduledStep] = []
        for step in scheduledSteps.reversed() {
            result.append(step)
        }

        // Anchor in-progress levain to its real fed time and close the gap.
        // Only anchor when the peak hasn't passed yet — otherwise the levain
        // hasn't been built and the schedule should use normal backward scheduling.
        if let ctx = input.levainContext,
           let levainIdx = result.firstIndex(where: { $0.levainElapsedMinutes != nil }),
           ctx.remainingMinutes() > 0
        {
            let old = result[levainIdx]
            let levainEnd = ctx.fedAt.addingTimeInterval(ctx.expectedPeakMinutes * 60)

            // Snap the preceding buildLevain (mix) step to just before the feed time
            if levainIdx > 0, result[levainIdx - 1].stepTypeID == .buildLevain {
                let mix = result[levainIdx - 1]
                let mixStart = ctx.fedAt.addingTimeInterval(-mix.durationMinutes * 60)
                result[levainIdx - 1] = ScheduledStep(
                    methodStepID: mix.methodStepID,
                    stepTypeID: mix.stepTypeID,
                    label: mix.label,
                    classification: mix.classification,
                    startTime: mixStart,
                    endTime: ctx.fedAt,
                    durationMinutes: mix.durationMinutes,
                    requiresTempReading: mix.requiresTempReading
                )
            }

            result[levainIdx] = ScheduledStep(
                methodStepID: old.methodStepID,
                stepTypeID: old.stepTypeID,
                label: old.label,
                classification: old.classification,
                startTime: ctx.fedAt,
                endTime: levainEnd,
                durationMinutes: old.durationMinutes,
                subSteps: old.subSteps,
                requiresTempReading: old.requiresTempReading,
                levainElapsedMinutes: old.levainElapsedMinutes
            )

            let nextIdx = levainIdx + 1
            if nextIdx < result.count {
                let next = result[nextIdx]
                let gap = next.startTime.timeIntervalSince(levainEnd)

                if gap > 0, next.classification == .passiveFlexible {
                    let methodFlex = method.first { $0.stepTypeID == next.stepTypeID }
                    let maxDuration = methodFlex?.effectiveFlexRange?.upperBound
                        ?? next.durationMinutes
                    let extendBy = min(gap, (maxDuration - next.durationMinutes) * 60)

                    if extendBy > 0 {
                        result[nextIdx] = ScheduledStep(
                            methodStepID: next.methodStepID,
                            stepTypeID: next.stepTypeID,
                            label: next.label,
                            classification: next.classification,
                            startTime: next.startTime.addingTimeInterval(-extendBy),
                            endTime: next.endTime,
                            durationMinutes: next.durationMinutes + (extendBy / 60.0),
                            subSteps: next.subSteps,
                            requiresTempReading: next.requiresTempReading
                        )
                        print("[ScheduleBuilder] extended \(next.label) earlier by \(Int(extendBy / 60))min to close levain gap")
                    }
                }
            }
        }

        // Enforce earliest start: shift pre-flex steps forward, compress flex step
        let firstNonLevain = result.first(where: { $0.levainElapsedMinutes == nil })
        let shiftAnchor = firstNonLevain?.startTime ?? result.first?.startTime
        print("[ScheduleBuilder] pre-shift check: earliestStart=\(input.earliestStartTime?.description ?? "nil") shiftAnchor=\(shiftAnchor?.description ?? "nil") (\(firstNonLevain?.label ?? result.first?.label ?? "nil"))")
        for (i, s) in result.enumerated() {
            print("[ScheduleBuilder]   [\(i)] \(s.label) start=\(s.startTime) dur=\(Int(s.durationMinutes))min levainElapsed=\(s.levainElapsedMinutes.map { String(Int($0)) } ?? "nil")")
        }
        if let earliest = input.earliestStartTime,
           let firstStart = shiftAnchor,
           firstStart < earliest
        {
            let delay = earliest.timeIntervalSince(firstStart)
            print("[ScheduleBuilder] earliest=\(earliest) firstStart=\(firstStart) delay=\(Int(delay/60))min")

            if let flexIdx = result.indices.max(by: { a, b in
                result[a].classification != .passiveFlexible ? true
                    : result[b].classification != .passiveFlexible ? false
                    : result[a].durationMinutes < result[b].durationMinutes
            }), result[flexIdx].classification == .passiveFlexible {
                let flexStep = result[flexIdx]
                let newDuration = flexStep.durationMinutes - (delay / 60.0)
                let methodFlex = method.first { $0.stepTypeID == flexStep.stepTypeID }
                let minDuration = methodFlex?.effectiveFlexRange?.lowerBound ?? 0
                print("[ScheduleBuilder] flexStep=\(flexStep.label) idx=\(flexIdx) oldDur=\(Int(flexStep.durationMinutes))min newDur=\(Int(newDuration))min min=\(Int(minDuration))min")

                if newDuration >= minDuration {
                    print("[ScheduleBuilder] shifting \(flexIdx) steps forward by \(Int(delay/60))min")
                    for i in 0 ..< flexIdx {
                        let old = result[i]
                        print("[ScheduleBuilder]   [\(i)] \(old.label) start=\(old.startTime) dur=\(Int(old.durationMinutes))min levainElapsed=\(old.levainElapsedMinutes.map { String(Int($0)) } ?? "nil")")
                        // An in-progress levain is fermenting in the jar: pin it to its
                        // real fed time and its true peak duration. Never stretch it to
                        // absorb target-anchoring slack — that belongs to the flex step
                        // (compressed below). Re-gluing buildLevain happens after the loop.
                        if old.levainElapsedMinutes != nil,
                           let ctx = input.levainContext, ctx.remainingMinutes() > 0 {
                            let fedAt = ctx.fedAt
                            let levainEnd = fedAt.addingTimeInterval(ctx.expectedPeakMinutes * 60)
                            print("[ScheduleBuilder]   → levain: fedAt=\(fedAt) levainEnd=\(levainEnd)")
                            result[i] = ScheduledStep(
                                methodStepID: old.methodStepID,
                                stepTypeID: old.stepTypeID,
                                label: old.label,
                                classification: old.classification,
                                startTime: fedAt,
                                endTime: levainEnd,
                                durationMinutes: ctx.expectedPeakMinutes,
                                subSteps: old.subSteps,
                                requiresTempReading: old.requiresTempReading,
                                levainElapsedMinutes: old.levainElapsedMinutes
                            )
                            continue
                        }
                        result[i] = ScheduledStep(
                            methodStepID: old.methodStepID,
                            stepTypeID: old.stepTypeID,
                            label: old.label,
                            classification: old.classification,
                            startTime: old.startTime.addingTimeInterval(delay),
                            endTime: old.endTime.addingTimeInterval(delay),
                            durationMinutes: old.durationMinutes,
                            subSteps: old.subSteps.map { sub in
                                ScheduledStep(
                                    methodStepID: sub.methodStepID,
                                    stepTypeID: sub.stepTypeID,
                                    label: sub.label,
                                    classification: sub.classification,
                                    startTime: sub.startTime.addingTimeInterval(delay),
                                    endTime: sub.endTime.addingTimeInterval(delay),
                                    durationMinutes: sub.durationMinutes,
                                    requiresTempReading: sub.requiresTempReading
                                )
                            },
                            requiresTempReading: old.requiresTempReading,
                            levainElapsedMinutes: old.levainElapsedMinutes
                        )
                    }
                    result[flexIdx] = ScheduledStep(
                        methodStepID: flexStep.methodStepID,
                        stepTypeID: flexStep.stepTypeID,
                        label: flexStep.label,
                        classification: flexStep.classification,
                        startTime: flexStep.startTime.addingTimeInterval(delay),
                        endTime: flexStep.endTime,
                        durationMinutes: newDuration,
                        subSteps: flexStep.subSteps,
                        requiresTempReading: flexStep.requiresTempReading
                    )

                    print("[ScheduleBuilder] after shift:")
                    for i in 0 ... flexIdx {
                        print("[ScheduleBuilder]   [\(i)] \(result[i].label) start=\(result[i].startTime) end=\(result[i].endTime) dur=\(Int(result[i].durationMinutes))min")
                    }
                    for i in 0 ..< flexIdx where result[i].classification == .handsOn {
                        let shifted = result[i]
                        let conflicts = AvailabilityResolver.overlaps(
                            start: shifted.startTime, end: shifted.endTime, blocks: unavailableBlocks
                        )
                        if !conflicts.isEmpty {
                            let block = conflicts.first!
                            return .conflict(ScheduleConflict(
                                conflictingStepLabel: shifted.label,
                                conflictingWindowName: block.sourceName ?? "your available hours",
                                conflictingWindowStart: block.start,
                                conflictingWindowEnd: block.end,
                                message: "\(shifted.label) would land at \(shifted.startTime.formatted(date: .omitted, time: .shortened)) during \(block.sourceName ?? "your available hours"). Try a later bread-ready time.",
                                suggestedAlternativeTime: nil
                            ))
                        }
                    }
                } else {
                    print("[ScheduleBuilder] flex compress rejected: \(Int(newDuration))min < min \(Int(minDuration))min")
                }
            } else {
                print("[ScheduleBuilder] no flex step found to absorb delay")
            }
        }

        // Re-glue Build Levain to the (pinned) levain wait so no idle gap can open
        // between mixing the levain and waiting for it to peak — they're one continuous
        // process. The earliest-start shift can move buildLevain without moving the
        // fed-time-pinned wait; this restores the invariant build.end == wait.start.
        // No-op when there is no in-progress levain (no levainElapsedMinutes step).
        if let waitIdx = result.firstIndex(where: { $0.levainElapsedMinutes != nil }),
           waitIdx > 0,
           result[waitIdx - 1].stepTypeID == .buildLevain {
            let mix = result[waitIdx - 1]
            let waitStart = result[waitIdx].startTime
            result[waitIdx - 1] = ScheduledStep(
                methodStepID: mix.methodStepID,
                stepTypeID: mix.stepTypeID,
                label: mix.label,
                classification: mix.classification,
                startTime: waitStart.addingTimeInterval(-mix.durationMinutes * 60),
                endTime: waitStart,
                durationMinutes: mix.durationMinutes,
                subSteps: mix.subSteps,
                requiresTempReading: mix.requiresTempReading,
                levainElapsedMinutes: mix.levainElapsedMinutes
            )
        }

        // Validate all flexible steps stay within their flex range
        for methodStep in method where methodStep.stepType.classification == .passiveFlexible {
            guard let flexRange = methodStep.effectiveFlexRange,
                  let scheduled = result.first(where: { $0.methodStepID == methodStep.id })
            else { continue }
            let actualDuration = scheduled.durationMinutes
            if actualDuration < flexRange.lowerBound || actualDuration > flexRange.upperBound {
                let hours = Int(actualDuration / 60)
                let maxHours = Int(flexRange.upperBound / 60)
                let minHours = Int(flexRange.lowerBound / 60)
                return .conflict(ScheduleConflict(
                    conflictingStepLabel: scheduled.label,
                    conflictingWindowName: "schedule constraint",
                    message: "\(scheduled.label) would be \(hours)h — needs to be between \(minHours)h and \(maxHours)h. Try a different bread-ready time.",
                    suggestedAlternativeTime: nil
                ))
            }
        }

        // Same-day recipes: verify no step starts during unavailable hours
        let isSameDay = !method.contains { $0.stepTypeID == .coldRetard }
        if isSameDay {
            for scheduled in result {
                for block in unavailableBlocks {
                    if scheduled.startTime >= block.start, scheduled.startTime < block.end {
                        return .conflict(ScheduleConflict(
                            conflictingStepLabel: scheduled.label,
                            conflictingWindowName: block.sourceName ?? "your available hours",
                            conflictingWindowStart: block.start,
                            conflictingWindowEnd: block.end,
                            message: "\(scheduled.label) would start at \(scheduled.startTime.formatted(date: .omitted, time: .shortened)) during \(block.sourceName ?? "your available hours"). Try a later bread-ready time.",
                            suggestedAlternativeTime: nil
                        ))
                    }
                }
            }
        }

        return .success(result)
    }

    // MARK: - Fold Sub-Scheduling

    private static func scheduleFolds(
        bulkStart: Date,
        bulkEnd: Date,
        foldCount: Int,
        spacingFraction: Double,
        inclusionAtFold: Int?,
        unavailableBlocks: [UnavailableBlock],
        calendar: Calendar
    ) -> [ScheduledStep] {
        let bulkDurationSeconds = bulkEnd.timeIntervalSince(bulkStart)
        let foldWindowSeconds = bulkDurationSeconds * spacingFraction
        let spacingSeconds = foldWindowSeconds / Double(foldCount + 1)
        let foldDurationMinutes = 3.0
        let foldToleranceMinutes = 15.0

        var folds: [ScheduledStep] = []

        for i in 1 ... foldCount {
            let idealTime = bulkStart.addingTimeInterval(spacingSeconds * Double(i))
            let idealEnd = idealTime.addingTimeInterval(foldDurationMinutes * 60)

            // Check for conflicts and shift if needed
            let foldStart: Date
            let overlapping = AvailabilityResolver.overlaps(
                start: idealTime,
                end: idealEnd,
                blocks: unavailableBlocks
            )

            if overlapping.isEmpty {
                foldStart = idealTime
            } else if let clearSlot = findClearSlot(
                idealTime: idealTime,
                duration: foldDurationMinutes * 60,
                tolerance: foldToleranceMinutes * 60,
                blocks: unavailableBlocks,
                calendar: calendar
            ) {
                foldStart = clearSlot
            } else {
                continue
            }

            let fold = ScheduledStep(
                methodStepID: UUID(),
                stepTypeID: .stretchAndFold,
                label: "Fold \(i) of \(foldCount)",
                classification: .handsOn,
                startTime: foldStart,
                endTime: foldStart.addingTimeInterval(foldDurationMinutes * 60),
                durationMinutes: foldDurationMinutes,
                requiresTempReading: true
            )
            folds.append(fold)

            // Add inclusions step at the designated fold
            if let inclusionFold = inclusionAtFold, i == inclusionFold {
                let inclusionStart = fold.endTime
                folds.append(ScheduledStep(
                    methodStepID: UUID(),
                    stepTypeID: .addInclusions,
                    label: "Add Inclusions",
                    classification: .handsOn,
                    startTime: inclusionStart,
                    endTime: inclusionStart.addingTimeInterval(2 * 60),
                    durationMinutes: 2
                ))
            }
        }

        return folds
    }

    /// Tries to find a clear time slot within ±tolerance of the ideal time.
    private static func findClearSlot(
        idealTime: Date,
        duration: TimeInterval,
        tolerance: TimeInterval,
        blocks: [UnavailableBlock],
        calendar _: Calendar
    ) -> Date? {
        // Try every minute within ±tolerance
        let stepSeconds = 60.0
        for offset in stride(from: 0.0, through: tolerance, by: stepSeconds) {
            // Try earlier
            let earlier = idealTime.addingTimeInterval(-offset)
            if AvailabilityResolver.overlaps(
                start: earlier,
                end: earlier.addingTimeInterval(duration),
                blocks: blocks
            ).isEmpty {
                return earlier
            }

            // Try later
            if offset > 0 {
                let later = idealTime.addingTimeInterval(offset)
                if AvailabilityResolver.overlaps(
                    start: later,
                    end: later.addingTimeInterval(duration),
                    blocks: blocks
                ).isEmpty {
                    return later
                }
            }
        }
        return nil
    }

    // MARK: - Conflict Resolution

    /// Attempts to resolve a conflict by adjusting adjacent flexible steps.
    ///
    /// Returns nil on success (step placed, scheduledSteps and cursor mutated).
    /// Returns a ScheduleResult.conflict on failure.
    private static func resolveConflict(
        step: MethodStep,
        tentativeStart _: Date,
        tentativeEnd _: Date,
        duration: Double,
        conflicts: [UnavailableBlock],
        scheduledSteps: inout [ScheduledStep],
        cursor: inout Date,
        unavailableBlocks: [UnavailableBlock],
        calendar: Calendar
    ) -> ScheduleResult? {
        // Strategy: push the hands-on step earlier, past the conflict.
        // If the last scheduled step (next in time, since we're going backwards)
        // is passiveFlexible, we can expand it to absorb the gap.
        guard let conflict = conflicts.first else { return nil }

        // Move the step to just before the conflict block starts
        let shiftedEnd = conflict.start
        let shiftedStart = calendar.date(
            byAdding: .minute,
            value: -Int(duration),
            to: shiftedEnd
        ) ?? shiftedEnd

        // Check the shifted position is also clear
        let shiftedConflicts = AvailabilityResolver.overlaps(
            start: shiftedStart,
            end: shiftedEnd,
            blocks: unavailableBlocks
        )

        if shiftedConflicts.isEmpty {
            // Check if we need to expand a flexible step to fill the gap
            if let lastIdx = scheduledSteps.indices.last {
                let lastStep = scheduledSteps[lastIdx]
                if lastStep.classification == .passiveFlexible {
                    // Expand the flexible step: its start stays, end moves to where cursor was
                    let expandedStep = ScheduledStep(
                        methodStepID: lastStep.methodStepID,
                        stepTypeID: lastStep.stepTypeID,
                        label: lastStep.label,
                        classification: lastStep.classification,
                        startTime: shiftedEnd,
                        endTime: lastStep.endTime,
                        durationMinutes: lastStep.endTime.timeIntervalSince(shiftedEnd) / 60.0,
                        subSteps: lastStep.subSteps,
                        requiresTempReading: lastStep.requiresTempReading
                    )
                    scheduledSteps[lastIdx] = expandedStep
                }
            }

            scheduledSteps.append(ScheduledStep(
                methodStepID: step.id,
                stepTypeID: step.stepTypeID,
                label: step.stepType.label,
                classification: step.stepType.classification,
                startTime: shiftedStart,
                endTime: shiftedEnd,
                durationMinutes: duration,
                requiresTempReading: step.stepType.requiresTempReading
            ))
            cursor = shiftedStart
            return nil // Success
        }

        // Could not resolve locally — return a conflict
        let block = conflicts.first ?? conflict
        return .conflict(ScheduleConflict(
            conflictingStepLabel: step.stepType.label,
            conflictingWindowName: block.sourceName ?? "your available hours",
            conflictingWindowStart: block.start,
            conflictingWindowEnd: block.end,
            message: "\(step.stepType.label) conflicts with \(block.sourceName ?? "your available hours"). Try a different bread-ready time.",
            suggestedAlternativeTime: shiftedEnd
        ))
    }

    // MARK: - Bulk Ferment Fold Repositioning

    /// Slides already-scheduled steps earlier to accommodate Bulk Ferment repositioning.
    ///
    /// When Bulk Ferment's fold window conflicts with an unavailable block, this
    /// shifts intervening steps (Shape, etc.) earlier by `delta` seconds and expands
    /// the nearest `passiveFlexible` step (Cold Retard) to absorb the gap.
    ///
    /// Returns nil on success, or a conflict if validation fails.
    private static func repositionForFoldAvailability(
        delta: TimeInterval,
        scheduledSteps: inout [ScheduledStep],
        unavailableBlocks: [UnavailableBlock],
        method: [MethodStep],
        calendar _: Calendar
    ) -> ScheduleResult? {
        guard delta > 0 else { return nil }

        var flexIdx: Int?
        for i in stride(from: scheduledSteps.count - 1, through: 0, by: -1) {
            if scheduledSteps[i].classification == .passiveFlexible {
                flexIdx = i
                break
            }
        }

        guard let flexIdx else {
            return .conflict(ScheduleConflict(
                conflictingStepLabel: "Bulk Ferment",
                conflictingWindowName: "schedule constraint",
                message: "Bulk Ferment folds conflict with an unavailable window and no flexible step can absorb the shift. Try a different bread-ready time.",
                suggestedAlternativeTime: nil
            ))
        }

        // Slide all steps after the flexible step earlier by delta
        for i in (flexIdx + 1) ..< scheduledSteps.count {
            let old = scheduledSteps[i]
            let newStart = old.startTime.addingTimeInterval(-delta)
            let newEnd = old.endTime.addingTimeInterval(-delta)

            if old.classification == .handsOn {
                let conflicts = AvailabilityResolver.overlaps(
                    start: newStart, end: newEnd, blocks: unavailableBlocks
                )
                if !conflicts.isEmpty {
                    let block = conflicts.first!
                    return .conflict(ScheduleConflict(
                        conflictingStepLabel: old.label,
                        conflictingWindowName: block.sourceName ?? "your available hours",
                        conflictingWindowStart: block.start,
                        conflictingWindowEnd: block.end,
                        message: "\(old.label) cannot be rescheduled to fit — conflicts with \(block.sourceName ?? "your available hours"). Try a different bread-ready time.",
                        suggestedAlternativeTime: nil
                    ))
                }
            }

            scheduledSteps[i] = ScheduledStep(
                methodStepID: old.methodStepID,
                stepTypeID: old.stepTypeID,
                label: old.label,
                classification: old.classification,
                startTime: newStart,
                endTime: newEnd,
                durationMinutes: old.durationMinutes,
                subSteps: old.subSteps,
                requiresTempReading: old.requiresTempReading,
                levainElapsedMinutes: old.levainElapsedMinutes
            )
        }

        // Expand the flexible step: start moves earlier, end stays fixed
        let flex = scheduledSteps[flexIdx]
        let newFlexStart = flex.startTime.addingTimeInterval(-delta)
        let newFlexDuration = flex.endTime.timeIntervalSince(newFlexStart) / 60.0

        let flexMethodStep = method.first { $0.stepTypeID == flex.stepTypeID }
        if let flexRange = flexMethodStep?.effectiveFlexRange,
           newFlexDuration > flexRange.upperBound
        {
            let maxHours = Int(flexRange.upperBound / 60)
            return .conflict(ScheduleConflict(
                conflictingStepLabel: flex.label,
                conflictingWindowName: "schedule constraint",
                message: "\(flex.label) would need to be \(Int(newFlexDuration / 60))h — max is \(maxHours)h. Try an earlier bread-ready time.",
                suggestedAlternativeTime: nil
            ))
        }

        scheduledSteps[flexIdx] = ScheduledStep(
            methodStepID: flex.methodStepID,
            stepTypeID: flex.stepTypeID,
            label: flex.label,
            classification: flex.classification,
            startTime: newFlexStart,
            endTime: flex.endTime,
            durationMinutes: newFlexDuration,
            subSteps: flex.subSteps,
            requiresTempReading: flex.requiresTempReading,
            levainElapsedMinutes: flex.levainElapsedMinutes
        )

        return nil
    }

    // MARK: - Presence Group Interaction Moments

    /// Calculates the interaction moments for a group of consecutive `requiresPresence` steps.
    ///
    /// Starting from `index` in the reversed method, collects all consecutive presence steps
    /// and returns the moments where user action is needed (step starts, ends, sub-step transitions).
    private static func presenceGroupInteractionMoments(
        from index: Int,
        in reversedMethod: [MethodStep],
        groupEnd: Date,
        kitchenTemp: Double,
        peakProfile: StarterPeakProfile?,
        calendar: Calendar
    ) -> (moments: [Date], groupDuration: Double) {
        var moments: [Date] = []
        var totalDuration: Double = 0
        var stepEnd = groupEnd

        var i = index
        while i < reversedMethod.count {
            let step = reversedMethod[i]
            guard step.stepType.requiresPresence else { break }

            let dur = TemperatureCalculator.effectiveDuration(
                for: step, kitchenTemp: kitchenTemp, peakProfile: peakProfile
            )
            let stepStart = calendar.date(byAdding: .minute, value: -Int(dur), to: stepEnd)
                ?? stepEnd

            moments.append(stepStart)
            moments.append(stepEnd)

            if !step.subSteps.isEmpty {
                var subCursor = stepStart
                for sub in step.subSteps {
                    let subDur = sub.effectiveDuration
                    subCursor = subCursor.addingTimeInterval(subDur * 60)
                    moments.append(subCursor)
                }
            }

            totalDuration += dur
            stepEnd = stepStart
            i += 1
        }

        let unique = Array(Set(moments)).sorted()
        return (moments: unique, groupDuration: totalDuration)
    }

    // MARK: - Flex Compression Detection

    struct FlexCompressionDetail {
        let stepLabel: String
        let defaultDurationMinutes: Double
        let actualDurationMinutes: Double
    }

    static func flexCompressionDetails(
        steps: [ScheduledStep],
        recipe: Recipe
    ) -> [FlexCompressionDetail] {
        var details: [FlexCompressionDetail] = []
        for methodStep in recipe.method where methodStep.stepType.classification == .passiveFlexible {
            guard let scheduled = steps.first(where: { $0.methodStepID == methodStep.id }) else { continue }
            let defaultDuration = methodStep.effectiveDuration
            if scheduled.durationMinutes < defaultDuration {
                details.append(FlexCompressionDetail(
                    stepLabel: scheduled.label,
                    defaultDurationMinutes: defaultDuration,
                    actualDurationMinutes: scheduled.durationMinutes
                ))
            }
        }
        return details
    }
}
