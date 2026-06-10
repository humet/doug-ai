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
        // Record the elapsed time only when it's plausible. An implausible value
        // (peak marked days late, or before the feed) is left nil so it never
        // pollutes the scheduler's time-to-peak averages.
        let minutes = peakTime.timeIntervalSince(timestamp) / 60.0
        timeToPeakMinutes = StarterPeakProfile.isPlausibleTimeToPeak(minutes) ? minutes : nil
    }

    /// Records an estimated peak ("it peaked while I slept"): timestamp only.
    /// `timeToPeakMinutes` stays nil so an estimate never feeds the scheduler's
    /// time-to-peak averages.
    func markEstimatedPeak(at peakTime: Date) {
        peakTimestamp = peakTime
        timeToPeakMinutes = nil
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
