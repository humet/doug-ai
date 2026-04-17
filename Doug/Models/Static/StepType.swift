import Foundation

// MARK: - Step Type ID

enum StepTypeID: String, CaseIterable, Codable {
    case buildLevain
    case autolyse
    case mix
    case bulkFerment
    case stretchAndFold
    case addInclusions
    case shape
    case coldRetard
    case preheat
    case bakeCovered
    case bakeUncovered
}

// MARK: - Step Classification

enum StepClassification: String, Codable {
    case handsOn
    case passiveFlexible
    case passiveFixed
}

// MARK: - Step Type (Template)

struct StepType: Identifiable {
    let id: StepTypeID
    let label: String
    let classification: StepClassification
    let baseDurationMinutes: Double
    let isTemperatureAdjusted: Bool
    let referenceTemperatureCelsius: Double?
    let flexRange: ClosedRange<Double>?
    let requiresTempReading: Bool
    let instructionText: String
    let notificationText: String
    let successSignal: String
}
