import Foundation

struct MethodStep: Identifiable {
    let id: UUID
    let stepTypeID: StepTypeID
    let durationOverrideMinutes: Double?
    let flexRangeOverride: ClosedRange<Double>?
    let foldCount: Int?
    let degreeHourTarget: Double?
    let foldSpacingFraction: Double?
    let inclusionAtFold: Int?
    let bakeTemperatureCelsius: Int?
    let levainBuildRatio: (starter: Int, flour: Int, water: Int)?
    let subSteps: [MethodStep]

    var stepType: StepType {
        StepTypeRegistry.type(for: stepTypeID)
    }

    var effectiveDuration: Double {
        durationOverrideMinutes ?? stepType.baseDurationMinutes
    }

    var effectiveFlexRange: ClosedRange<Double>? {
        flexRangeOverride ?? stepType.flexRange
    }

    init(
        stepTypeID: StepTypeID,
        durationOverrideMinutes: Double? = nil,
        flexRangeOverride: ClosedRange<Double>? = nil,
        foldCount: Int? = nil,
        degreeHourTarget: Double? = nil,
        foldSpacingFraction: Double? = nil,
        inclusionAtFold: Int? = nil,
        bakeTemperatureCelsius: Int? = nil,
        levainBuildRatio: (starter: Int, flour: Int, water: Int)? = nil,
        subSteps: [MethodStep] = []
    ) {
        id = UUID()
        self.stepTypeID = stepTypeID
        self.durationOverrideMinutes = durationOverrideMinutes
        self.flexRangeOverride = flexRangeOverride
        self.foldCount = foldCount
        self.degreeHourTarget = degreeHourTarget
        self.foldSpacingFraction = foldSpacingFraction
        self.inclusionAtFold = inclusionAtFold
        self.bakeTemperatureCelsius = bakeTemperatureCelsius
        self.levainBuildRatio = levainBuildRatio
        self.subSteps = subSteps
    }
}
