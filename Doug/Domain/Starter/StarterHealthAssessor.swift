import Foundation

/// Evaluates starter health based on feed history and peak-time trends.
enum StarterHealthAssessor {
    /// Assesses the current health status of the starter.
    ///
    /// - Parameters:
    ///   - profile: The starter's profile (storage type, thresholds).
    ///   - feedLogs: Recent feed logs, sorted by timestamp descending.
    ///   - now: Current date (injectable for testing).
    /// - Returns: The assessed health status.
    static func assess(
        profile: StarterProfileInput,
        feedLogs: [FeedLogInput],
        now: Date = Date()
    ) -> StarterHealthStatus {
        guard let lastFeed = feedLogs.first else {
            return .needsRevival // Never fed = needs revival
        }

        let daysSinceLastFeed = now.timeIntervalSince(lastFeed.timestamp) / 86400.0

        // Check if significantly overdue → needs revival
        if daysSinceLastFeed > profile.needsRevivalDaysThreshold {
            return .needsRevival
        }

        // Check if peak times are trending slow → needs revival
        if isPeakTimeTrendingSlow(feedLogs: feedLogs, profile: profile) {
            return .needsRevival
        }

        // Check if moderately overdue → needs a feed
        if daysSinceLastFeed > profile.needsFeedDaysThreshold {
            return .needsFeed
        }

        return .readyToBake
    }

    /// Checks whether recent time-to-peak readings are significantly slower
    /// than the user's historical average.
    private static func isPeakTimeTrendingSlow(
        feedLogs: [FeedLogInput],
        profile: StarterProfileInput
    ) -> Bool {
        let recentWithPeak = feedLogs.prefix(3).filter { $0.timeToPeakMinutes != nil }
        guard recentWithPeak.count >= 2 else { return false }

        guard let avgPeak = profile.averageTimeToPeakMinutes, avgPeak > 0 else {
            return false
        }

        let recentAvg = recentWithPeak.compactMap(\.timeToPeakMinutes).reduce(0, +)
            / Double(recentWithPeak.count)

        // If recent average is >50% slower than historical, flag it
        return recentAvg > avgPeak * 1.5
    }
}

// MARK: - Input Types (decoupled from SwiftData)

struct StarterProfileInput {
    let storageType: StarterStorageType
    let maintenanceCycleDays: Double
    let needsFeedDaysThreshold: Double
    let needsRevivalDaysThreshold: Double
    let averageTimeToPeakMinutes: Double?
}

struct FeedLogInput {
    let timestamp: Date
    let ratioStarter: Int
    let ratioFlour: Int
    let ratioWater: Int
    let flourType: String
    let kitchenTemperatureCelsius: Double
    let timeToPeakMinutes: Double?
}

extension StarterProfileInput {
    init(from model: StarterProfile) {
        storageType = model.starterStorageType
        maintenanceCycleDays = model.maintenanceCycleDays
        needsFeedDaysThreshold = model.needsFeedDaysThreshold
        needsRevivalDaysThreshold = model.needsRevivalDaysThreshold
        averageTimeToPeakMinutes = model.averageTimeToPeakMinutes
    }
}

extension FeedLogInput {
    init(from model: StarterFeedLog) {
        timestamp = model.timestamp
        ratioStarter = model.ratioStarter
        ratioFlour = model.ratioFlour
        ratioWater = model.ratioWater
        flourType = model.flourType
        kitchenTemperatureCelsius = model.kitchenTemperatureCelsius
        timeToPeakMinutes = model.timeToPeakMinutes
    }
}
