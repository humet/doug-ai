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

    init(
        recipe: Recipe,
        targetBreadReadyTime: Date,
        kitchenTemperatureCelsius: Double,
        availability: AvailabilityInput,
        unavailableWindows: [WindowInput] = [],
        calendar: Calendar = .current,
        peakProfile: StarterPeakProfile? = nil
    ) {
        self.recipe = recipe
        self.targetBreadReadyTime = targetBreadReadyTime
        self.kitchenTemperatureCelsius = kitchenTemperatureCelsius
        self.availability = availability
        self.unavailableWindows = unavailableWindows
        self.calendar = calendar
        self.peakProfile = peakProfile
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

    init(
        methodStepID: UUID,
        stepTypeID: StepTypeID,
        label: String,
        classification: StepClassification,
        startTime: Date,
        endTime: Date,
        durationMinutes: Double,
        subSteps: [ScheduledStep] = [],
        requiresTempReading: Bool = false
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
        for methodStep in method.reversed() {
            let stepType = methodStep.stepType
            let duration = TemperatureCalculator.effectiveDuration(
                for: methodStep,
                kitchenTemp: input.kitchenTemperatureCelsius,
                peakProfile: input.peakProfile
            )

            let tentativeEnd = cursor
            let tentativeStart = calendar.date(
                byAdding: .minute,
                value: -Int(duration),
                to: tentativeEnd
            ) ?? tentativeEnd

            switch stepType.classification {
            case .passiveFixed, .passiveFlexible:
                // Passive steps can run through unavailable windows
                var step = ScheduledStep(
                    methodStepID: methodStep.id,
                    stepTypeID: methodStep.stepTypeID,
                    label: stepType.label,
                    classification: stepType.classification,
                    startTime: tentativeStart,
                    endTime: tentativeEnd,
                    durationMinutes: duration,
                    requiresTempReading: stepType.requiresTempReading
                )

                // Sub-schedule folds within bulk ferment
                if methodStep.stepTypeID == .bulkFerment, let foldCount = methodStep.foldCount {
                    let folds = scheduleFolds(
                        bulkStart: tentativeStart,
                        bulkEnd: tentativeEnd,
                        foldCount: foldCount,
                        spacingFraction: methodStep.foldSpacingFraction ?? 0.67,
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

                scheduledSteps.append(step)
                cursor = tentativeStart

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
        return .success(scheduledSteps.reversed())
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
            } else {
                // Try shifting ±15 minutes to find a clear slot
                foldStart = findClearSlot(
                    idealTime: idealTime,
                    duration: foldDurationMinutes * 60,
                    tolerance: foldToleranceMinutes * 60,
                    blocks: unavailableBlocks,
                    calendar: calendar
                ) ?? idealTime // Fall back to ideal if no clear slot
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
}
