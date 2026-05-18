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
        switch profile.lifecycleState {
        case .active:
            .readyToBake
        case .activating:
            assessActivating(feedLogs: feedLogs, profile: profile)
        case .reviving:
            .needsRevival
        case .dormant:
            assessDormant(feedLogs: feedLogs, profile: profile, now: now)
        }
    }

    private static func assessDormant(
        feedLogs: [FeedLogInput],
        profile: StarterProfileInput,
        now: Date
    ) -> StarterHealthStatus {
        guard let lastFeed = feedLogs.first else {
            return .needsRevival
        }

        let daysSinceLastFeed = now.timeIntervalSince(lastFeed.timestamp) / 86400.0

        if daysSinceLastFeed > profile.needsRevivalDaysThreshold {
            return .needsRevival
        }

        if isPeakTimeTrendingSlow(feedLogs: feedLogs, profile: profile) {
            return .needsRevival
        }

        if daysSinceLastFeed > profile.needsFeedDaysThreshold {
            return .needsFeed
        }

        return .readyToBake
    }

    private static func assessActivating(
        feedLogs: [FeedLogInput],
        profile: StarterProfileInput
    ) -> StarterHealthStatus {
        let activationLogs = feedLogs.filter { $0.feedIntent == .activation }
        let recentPeaks = activationLogs.prefix(3).compactMap(\.timeToPeakMinutes)
        guard recentPeaks.count >= 2 else { return .needsFeed }

        if let avg = profile.activePeakAverageMinutes, avg > 0 {
            let recentAvg = recentPeaks.reduce(0, +) / Double(recentPeaks.count)
            if recentAvg > avg * 1.5 {
                return .needsRevival
            }
        }

        return .readyToBake
    }

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
    var lifecycleState: StarterLifecycleState = .dormant
    var activePeakAverageMinutes: Double?
}

struct FeedLogInput {
    let timestamp: Date
    let ratioStarter: Int
    let ratioFlour: Int
    let ratioWater: Int
    let flourType: String
    let kitchenTemperatureCelsius: Double
    let timeToPeakMinutes: Double?
    var starterGrams: Double? = nil
    var feedIntent: FeedIntent = .maintenance
}

