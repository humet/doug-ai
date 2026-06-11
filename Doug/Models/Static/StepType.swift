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
    case coldRetardBalls
    case temper
    case finalProof
    case panShape
    case bakeSheet
    case preheat
    case bake
    case bakeCovered
    case bakeUncovered
    case fridgeRest
    case holdStarter
    case activateStarter
    case waitForPeak
    case waitForLevainPeak
    case refeedAndRefrigerate
}

extension StepTypeID {
    /// Both fridge-fermentation steps: the bread retard (shaped loaf in a
    /// banneton) and the pizza retard (divided dough balls). The scheduler's
    /// overnight handling applies to either.
    var isColdRetard: Bool {
        self == .coldRetard || self == .coldRetardBalls
    }
}

// MARK: - Step Classification

enum StepClassification: String, Codable {
    case handsOn
    case passiveFlexible
    case passiveFixed
}

// MARK: - Staleness Info

struct StalenessInfo {
    let thresholdMinutes: Double
    let warning: String
    let salvageAdvice: String
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
    var requiresPresence: Bool = false
    let instructionText: String
    let notificationText: String
    let successSignal: String
    var staleness: StalenessInfo?
}
