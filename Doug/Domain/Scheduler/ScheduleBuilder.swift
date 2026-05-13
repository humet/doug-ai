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

    init(
        recipe: Recipe,
        targetBreadReadyTime: Date,
        kitchenTemperatureCelsius: Double,
        availability: AvailabilityInput,
        unavailableWindows: [WindowInput] = [],
        calendar: Calendar = .current,
        peakProfile: StarterPeakProfile? = nil,
        levainContext: LevainContext? = nil
    ) {
        self.recipe = recipe
        self.targetBreadReadyTime = targetBreadReadyTime
        self.kitchenTemperatureCelsius = kitchenTemperatureCelsius
        self.availability = availability
        self.unavailableWindows = unavailableWindows
        self.calendar = calendar
        self.peakProfile = peakProfile
        self.levainContext = levainContext
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
    let message: String
    let suggestedAlternativeTime: Date?
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
            if methodStep.stepTypeID == .buildLevain, let ctx = input.levainContext {
                let remaining = ctx.remainingMinutes()
                levainElapsed = ctx.elapsedMinutes()
                duration = remaining
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

                    let conflictingMoment = moments.first { moment in
                        !AvailabilityResolver.momentOverlaps(moment, blocks: unavailableBlocks).isEmpty
                    }

                    if let conflictingMoment {
                        let block = AvailabilityResolver.momentOverlaps(
                            conflictingMoment, blocks: unavailableBlocks
                        ).first!

                        let shiftAmount = conflictingMoment.timeIntervalSince(block.start)
                        let shiftedEnd = tentativeEnd.addingTimeInterval(-shiftAmount)
                        let shiftedStart = calendar.date(
                            byAdding: .minute, value: -Int(duration), to: shiftedEnd
                        ) ?? shiftedEnd

                        let shiftedMoments = moments.map { $0.addingTimeInterval(-shiftAmount) }
                        let stillConflicting = shiftedMoments.contains { moment in
                            !AvailabilityResolver.momentOverlaps(moment, blocks: unavailableBlocks).isEmpty
                        }

                        if stillConflicting {
                            return .conflict(ScheduleConflict(
                                conflictingStepLabel: stepType.label,
                                conflictingWindowName: "unavailable window",
                                message: "\(stepType.label) conflicts with an unavailable window and cannot be rescheduled. Try a different bread-ready time.",
                                suggestedAlternativeTime: nil
                            ))
                        }

                        // Expand the last scheduled flexible step (Cold Retard) to absorb the gap
                        if let lastIdx = scheduledSteps.indices.last,
                           scheduledSteps[lastIdx].classification == .passiveFlexible
                        {
                            let lastStep = scheduledSteps[lastIdx]
                            scheduledSteps[lastIdx] = ScheduledStep(
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
                        }

                        tentativeEnd = shiftedEnd
                        tentativeStart = shiftedStart
                    }
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

        // Reverse to chronological order and validate
        var result: [ScheduledStep] = []
        for step in scheduledSteps.reversed() {
            result.append(step)
        }

        // Validate Cold Retard flex range
        if let coldRetardStep = result.first(where: { $0.stepTypeID == .coldRetard }) {
            let coldRetardMethod = method.first(where: { $0.stepTypeID == .coldRetard })
            if let flexRange = coldRetardMethod?.effectiveFlexRange {
                let actualDuration = coldRetardStep.durationMinutes
                if actualDuration < flexRange.lowerBound || actualDuration > flexRange.upperBound {
                    let hours = Int(actualDuration / 60)
                    let maxHours = Int(flexRange.upperBound / 60)
                    let minHours = Int(flexRange.lowerBound / 60)
                    return .conflict(ScheduleConflict(
                        conflictingStepLabel: "Cold Retard",
                        conflictingWindowName: "schedule constraint",
                        message: "Cold Retard would be \(hours)h — needs to be between \(minHours)h and \(maxHours)h. Try a different bread-ready time.",
                        suggestedAlternativeTime: nil
                    ))
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
        return .conflict(ScheduleConflict(
            conflictingStepLabel: step.stepType.label,
            conflictingWindowName: "unavailable window",
            message: "\(step.stepType.label) conflicts with an unavailable window. Try a different bread-ready time.",
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
                    return .conflict(ScheduleConflict(
                        conflictingStepLabel: old.label,
                        conflictingWindowName: "unavailable window",
                        message: "\(old.label) cannot be rescheduled to fit. Try a different bread-ready time.",
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
}
