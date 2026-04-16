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

    func markPeak(for log: StarterFeedLog, profile: StarterProfile?, allLogs: [StarterFeedLog]) {
        log.markPeak(at: Date())
        updateProfileAverages(profile: profile, feedLogs: allLogs)
    }

    /// Recalculates the starter profile's average time-to-peak from feed history.
    func updateProfileAverages(profile: StarterProfile?, feedLogs: [StarterFeedLog]) {
        guard let profile else { return }

        let peakTimes = feedLogs.compactMap(\.timeToPeakMinutes)
        guard !peakTimes.isEmpty else { return }

        profile.averageTimeToPeakMinutes = peakTimes.reduce(0, +) / Double(peakTimes.count)
        profile.starterHealthStatus = healthStatus(profile: profile, feedLogs: feedLogs)
        profile.lastUpdated = Date()
    }

    /// Generates a revival plan for the starter.
    func startRevival(
        profile: StarterProfile?,
        availability: UserAvailability?,
        windows: [UnavailableWindow],
        modelContext: ModelContext
    ) -> RevivalPlan? {
        let avail = availability.map { AvailabilityInput(from: $0) }
            ?? AvailabilityInput(startHour: 6, startMinute: 30, endHour: 21, endMinute: 0)
        let windowInputs = windows.map { WindowInput(from: $0) }

        let feedPlans = RevivalPlanGenerator.generate(
            startTime: Date(),
            availability: avail,
            windows: windowInputs
        )

        let plan = RevivalPlan()
        plan.estimatedBakeReadyDate = RevivalPlanGenerator.estimatedBakeReadyDate(startTime: Date())
        modelContext.insert(plan)

        for feedPlan in feedPlans {
            let step = RevivalFeedStep(
                sequenceIndex: feedPlan.sequenceIndex,
                scheduledTime: feedPlan.scheduledTime,
                expectedPeakMinutes: feedPlan.expectedPeakMinutes,
                targetRatioStarter: feedPlan.ratioStarter,
                targetRatioFlour: feedPlan.ratioFlour,
                targetRatioWater: feedPlan.ratioWater
            )
            step.plan = plan
        }

        return plan
    }
}
