@testable import Doug
import Foundation
import SwiftData
import Testing

@MainActor
@Suite(.serialized)
struct StarterViewModelMarkPeakTests {
    private func makeContainer(
        lifecycle: StarterLifecycleState = .activating
    ) throws -> (ModelContainer, StarterProfile) {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: StarterProfile.self, StarterFeedLog.self,
            configurations: config
        )
        let profile = StarterProfile(storageType: .counter)
        profile.starterLifecycleState = lifecycle
        container.mainContext.insert(profile)
        return (container, profile)
    }

    private func makeActivationFeed(fedHoursAgo hours: Double, container: ModelContainer) -> StarterFeedLog {
        let log = StarterFeedLog(
            timestamp: Date().addingTimeInterval(-hours * 3600),
            ratioStarter: 1, ratioFlour: 5, ratioWater: 5,
            kitchenTemperatureCelsius: 22,
            feedIntent: .activation
        )
        container.mainContext.insert(log)
        return log
    }

    @Test func backdatedPeakRecordsDurationAndActivates() throws {
        let (container, profile) = try makeContainer()
        let log = makeActivationFeed(fedHoursAgo: 8, container: container)
        let viewModel = StarterViewModel()

        // Peaked 3 hours ago — a plausible 5h rise.
        let peakDate = Date().addingTimeInterval(-3 * 3600)
        viewModel.markPeak(for: log, at: peakDate, profile: profile, allLogs: [log])

        #expect(log.peakTimestamp == peakDate)
        let minutes = try #require(log.timeToPeakMinutes)
        #expect(abs(minutes - 300) < 1)
        #expect(profile.starterLifecycleState == .active)
        #expect(abs((profile.activePeakAverageMinutes ?? 0) - 300) < 1)
    }

    @Test func estimatedPeakLeavesDurationNilButStillActivates() throws {
        let (container, profile) = try makeContainer()
        profile.activePeakAverageMinutes = 300
        let log = makeActivationFeed(fedHoursAgo: 10, container: container)
        let viewModel = StarterViewModel()

        let estimate = viewModel.estimatedPeakDate(for: log, profile: profile)
        viewModel.markPeak(for: log, at: estimate, estimated: true, profile: profile, allLogs: [log])

        // The estimate lands at feed + average, is recorded as the peak
        // timestamp, but deliberately never contributes a duration.
        #expect(log.peakTimestamp == estimate)
        #expect(abs(estimate.timeIntervalSince(log.timestamp) - 300 * 60) < 1)
        #expect(log.timeToPeakMinutes == nil)
        #expect(profile.starterLifecycleState == .active)
        // The pre-existing average survives untouched.
        #expect(profile.activePeakAverageMinutes == 300)
    }

    @Test func implausiblyLateBackdateDropsDurationButStillActivates() throws {
        let (container, profile) = try makeContainer()
        let log = makeActivationFeed(fedHoursAgo: 80, container: container)
        let viewModel = StarterViewModel()

        // "Peaked" 3+ days after the feed — timestamp recorded, duration junked.
        viewModel.markPeak(for: log, at: Date(), profile: profile, allLogs: [log])

        #expect(log.peakTimestamp != nil)
        #expect(log.timeToPeakMinutes == nil)
        // The user confirmed the peak, so the explicit transition still runs —
        // estimated/implausible data must never strand the lifecycle.
        #expect(profile.starterLifecycleState == .active)
    }

    // MARK: - Primary action derivation

    @Test func primaryActionPerLifecycleState() {
        let viewModel = StarterViewModel()

        #expect(viewModel.primaryAction(
            lifecycleState: .dormant, healthStatus: .readyToBake,
            hasRisingFeed: false, hasUpcomingRecipe: false,
            hasRecentLevainFeed: false, bakeAwaitingLevainMix: false
        ) == .activateAndFeed)

        #expect(viewModel.primaryAction(
            lifecycleState: .dormant, healthStatus: .needsRevival,
            hasRisingFeed: false, hasUpcomingRecipe: false,
            hasRecentLevainFeed: false, bakeAwaitingLevainMix: false
        ) == .followRevival)

        #expect(viewModel.primaryAction(
            lifecycleState: .activating, healthStatus: .readyToBake,
            hasRisingFeed: true, hasUpcomingRecipe: false,
            hasRecentLevainFeed: false, bakeAwaitingLevainMix: false
        ) == .markPeak)

        #expect(viewModel.primaryAction(
            lifecycleState: .activating, healthStatus: .readyToBake,
            hasRisingFeed: false, hasUpcomingRecipe: false,
            hasRecentLevainFeed: false, bakeAwaitingLevainMix: false
        ) == .logActivationFeed)

        #expect(viewModel.primaryAction(
            lifecycleState: .active, healthStatus: .readyToBake,
            hasRisingFeed: false, hasUpcomingRecipe: true,
            hasRecentLevainFeed: false, bakeAwaitingLevainMix: false
        ) == .buildLevain)

        #expect(viewModel.primaryAction(
            lifecycleState: .active, healthStatus: .readyToBake,
            hasRisingFeed: false, hasUpcomingRecipe: true,
            hasRecentLevainFeed: true, bakeAwaitingLevainMix: false
        ) == .feedAndRefrigerate)

        #expect(viewModel.primaryAction(
            lifecycleState: .active, healthStatus: .readyToBake,
            hasRisingFeed: false, hasUpcomingRecipe: false,
            hasRecentLevainFeed: false, bakeAwaitingLevainMix: true
        ) == .waitForBake)

        #expect(viewModel.primaryAction(
            lifecycleState: .reviving, healthStatus: .needsRevival,
            hasRisingFeed: false, hasUpcomingRecipe: false,
            hasRecentLevainFeed: false, bakeAwaitingLevainMix: false
        ) == .followRevival)
    }
}
