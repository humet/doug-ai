@testable import Doug
import Foundation
import Testing

struct EarliestBakeEstimatorTests {
    private static let scheduleDuration: Double = 1200 // 20 hours in minutes

    @Test func activeStarterHasZeroActivationLead() {
        let estimate = EarliestBakeEstimator.estimate(
            lifecycleState: .active,
            stateChangedAt: Date(),
            lastActivationFeed: nil,
            activePeakAverage: nil,
            kitchenTempC: 23,
            scheduleDurationMinutes: Self.scheduleDuration
        )

        #expect(estimate.activationLeadMinutes == 0)
    }

    @Test func dormantStarterAddsActivationLead() {
        let estimate = EarliestBakeEstimator.estimate(
            lifecycleState: .dormant,
            stateChangedAt: Date(),
            lastActivationFeed: nil,
            activePeakAverage: 360,
            kitchenTempC: 23,
            scheduleDurationMinutes: Self.scheduleDuration
        )

        #expect(estimate.activationLeadMinutes == 360)
    }

    @Test func dormantWithoutHistoryUsesTemperatureEstimate() {
        let estimate = EarliestBakeEstimator.estimate(
            lifecycleState: .dormant,
            stateChangedAt: Date(),
            lastActivationFeed: nil,
            activePeakAverage: nil,
            kitchenTempC: 23,
            scheduleDurationMinutes: Self.scheduleDuration
        )

        // At 23°C, TemperatureCalculator returns 300 min (5h)
        #expect(estimate.activationLeadMinutes == 300)
    }

    @Test func activatingWithRisingFeedSubtractsElapsedTime() {
        let now = Date()
        let feedStart = now.addingTimeInterval(-120 * 60) // Fed 2 hours ago

        let feed = FeedLogInput(
            timestamp: feedStart,
            ratioStarter: 1, ratioFlour: 5, ratioWater: 5,
            flourType: "white", kitchenTemperatureCelsius: 23,
            timeToPeakMinutes: nil,
            feedIntent: .activation
        )

        let estimate = EarliestBakeEstimator.estimate(
            lifecycleState: .activating,
            stateChangedAt: feedStart,
            lastActivationFeed: feed,
            activePeakAverage: 300,
            kitchenTempC: 23,
            scheduleDurationMinutes: Self.scheduleDuration,
            now: now
        )

        // 300 - 120 = 180 minutes remaining
        #expect(abs(estimate.activationLeadMinutes - 180) < 1)
    }

    @Test func activatingWithPeakedFeedHasZeroLead() {
        let feed = FeedLogInput(
            timestamp: Date().addingTimeInterval(-300 * 60),
            ratioStarter: 1, ratioFlour: 5, ratioWater: 5,
            flourType: "white", kitchenTemperatureCelsius: 23,
            timeToPeakMinutes: 290,
            feedIntent: .activation
        )

        let estimate = EarliestBakeEstimator.estimate(
            lifecycleState: .activating,
            stateChangedAt: Date().addingTimeInterval(-7200),
            lastActivationFeed: feed,
            activePeakAverage: 300,
            kitchenTempC: 23,
            scheduleDurationMinutes: Self.scheduleDuration
        )

        #expect(estimate.activationLeadMinutes == 0)
    }

    @Test func earliestBreadReadySumsLeadAndSchedule() {
        let now = Date()
        let estimate = EarliestBakeEstimator.estimate(
            lifecycleState: .dormant,
            stateChangedAt: now,
            lastActivationFeed: nil,
            activePeakAverage: 360,
            kitchenTempC: 23,
            scheduleDurationMinutes: Self.scheduleDuration,
            now: now
        )

        let expectedMinutes = 360 + Self.scheduleDuration
        let expectedDate = now.addingTimeInterval(expectedMinutes * 60)
        #expect(abs(estimate.earliestBreadReady.timeIntervalSince(expectedDate)) < 1)
    }

    @Test func recipeDurationSumsAllSteps() {
        let duration = EarliestBakeEstimator.recipeDurationMinutes(
            recipe: RecipeBook.countryLoaf,
            kitchenTempC: 23
        )

        // Should be a reasonable total — roughly 20+ hours for a sourdough loaf
        #expect(duration > 1000) // >16 hours
        #expect(duration < 2400) // <40 hours
    }

    @Test func breakdownFormatsCorrectly() {
        let estimate = EarliestBakeEstimator.estimate(
            lifecycleState: .dormant,
            stateChangedAt: Date(),
            lastActivationFeed: nil,
            activePeakAverage: 360,
            kitchenTempC: 23,
            scheduleDurationMinutes: Self.scheduleDuration
        )

        #expect(estimate.breakdown.contains("activation"))
        #expect(estimate.breakdown.contains("bake"))
    }
}
