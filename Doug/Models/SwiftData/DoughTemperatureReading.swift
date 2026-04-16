import Foundation
import SwiftData

@Model
final class DoughTemperatureReading {
    var schedule: Schedule?
    var timestamp: Date
    var temperatureCelsius: Double
    var associatedStepTypeID: String?
    var sequenceNumber: Int
    var accumulatedDegreeHours: Double
    var aliquotRisePercent: Double?

    init(
        timestamp: Date,
        temperatureCelsius: Double,
        sequenceNumber: Int,
        accumulatedDegreeHours: Double,
        associatedStepTypeID: StepTypeID? = nil,
        aliquotRisePercent: Double? = nil
    ) {
        self.timestamp = timestamp
        self.temperatureCelsius = temperatureCelsius
        self.sequenceNumber = sequenceNumber
        self.accumulatedDegreeHours = accumulatedDegreeHours
        self.associatedStepTypeID = associatedStepTypeID?.rawValue
        self.aliquotRisePercent = aliquotRisePercent
    }
}
