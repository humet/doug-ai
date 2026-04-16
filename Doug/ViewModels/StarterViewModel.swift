import Foundation
import SwiftData
import Observation

@Observable
@MainActor
final class StarterViewModel {
    var showLogFeed = false

    // Feed entry form state
    var feedRatioStarter = 1
    var feedRatioFlour = 5
    var feedRatioWater = 5
    var feedFlourType = "white"
    var feedKitchenTemp = 22.0

    func healthStatus(
        profile: StarterProfile?,
        feedLogs: [StarterFeedLog]
    ) -> StarterHealthStatus {
        guard let profile else { return .needsFeed }

        let profileInput = StarterProfileInput(from: profile)
        let logInputs = feedLogs.map { FeedLogInput(from: $0) }

        return StarterHealthAssessor.assess(
            profile: profileInput,
            feedLogs: logInputs
        )
    }

    func nextFeedTime(
        profile: StarterProfile?,
        feedLogs: [StarterFeedLog],
        availability: UserAvailability?,
        windows: [UnavailableWindow],
        upcomingBakeStart: Date?
    ) -> Date? {
        guard let profile else { return nil }

        let avail = availability.map { AvailabilityInput(from: $0) }
            ?? AvailabilityInput(startHour: 6, startMinute: 30, endHour: 21, endMinute: 0)

        return FeedScheduler.nextFeedTime(
            lastFeedTime: feedLogs.first?.timestamp,
            cycleDays: profile.maintenanceCycleDays,
            upcomingBakeStart: upcomingBakeStart,
            availability: avail,
            windows: windows.map { WindowInput(from: $0) }
        )
    }

    func logFeed(modelContext: ModelContext) {
        let log = StarterFeedLog(
            ratioStarter: feedRatioStarter,
            ratioFlour: feedRatioFlour,
            ratioWater: feedRatioWater,
            flourType: feedFlourType,
            kitchenTemperatureCelsius: feedKitchenTemp
        )
        modelContext.insert(log)

        // Reset form
        feedRatioStarter = 1
        feedRatioFlour = 5
        feedRatioWater = 5
        feedFlourType = "white"

        showLogFeed = false
    }

    func markPeak(for log: StarterFeedLog) {
        log.markPeak(at: Date())
    }
}
