import Foundation
import SwiftData

@Model
final class StarterFeedLog {
    var timestamp: Date
    var ratioStarter: Int
    var ratioFlour: Int
    var ratioWater: Int
    var flourType: String
    var kitchenTemperatureCelsius: Double
    var peakTimestamp: Date?
    var timeToPeakMinutes: Double?

    init(
        timestamp: Date = Date(),
        ratioStarter: Int,
        ratioFlour: Int,
        ratioWater: Int,
        flourType: String = "white",
        kitchenTemperatureCelsius: Double
    ) {
        self.timestamp = timestamp
        self.ratioStarter = ratioStarter
        self.ratioFlour = ratioFlour
        self.ratioWater = ratioWater
        self.flourType = flourType
        self.kitchenTemperatureCelsius = kitchenTemperatureCelsius
    }

    func markPeak(at peakTime: Date) {
        peakTimestamp = peakTime
        timeToPeakMinutes = peakTime.timeIntervalSince(timestamp) / 60.0
    }

    var ratioDescription: String {
        "\(ratioStarter):\(ratioFlour):\(ratioWater)"
    }
}
