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
    var starterGrams: Double?
    var feedIntent: String = FeedIntent.maintenance.rawValue

    init(
        timestamp: Date = Date(),
        ratioStarter: Int,
        ratioFlour: Int,
        ratioWater: Int,
        flourType: String = "white",
        kitchenTemperatureCelsius: Double,
        starterGrams: Double? = nil,
        feedIntent: FeedIntent = .maintenance
    ) {
        self.timestamp = timestamp
        self.ratioStarter = ratioStarter
        self.ratioFlour = ratioFlour
        self.ratioWater = ratioWater
        self.flourType = flourType
        self.kitchenTemperatureCelsius = kitchenTemperatureCelsius
        self.starterGrams = starterGrams
        self.feedIntent = feedIntent.rawValue
    }

    var starterFeedIntent: FeedIntent {
        get { FeedIntent(rawValue: feedIntent) ?? .maintenance }
        set { feedIntent = newValue.rawValue }
    }

    func markPeak(at peakTime: Date) {
        peakTimestamp = peakTime
        timeToPeakMinutes = peakTime.timeIntervalSince(timestamp) / 60.0
    }

    var ratioDescription: String {
        "\(ratioStarter):\(ratioFlour):\(ratioWater)"
    }

    var flourGrams: Double? {
        guard let starterGrams, ratioStarter > 0 else { return nil }
        return starterGrams * Double(ratioFlour) / Double(ratioStarter)
    }

    var waterGrams: Double? {
        guard let starterGrams, ratioStarter > 0 else { return nil }
        return starterGrams * Double(ratioWater) / Double(ratioStarter)
    }
}
