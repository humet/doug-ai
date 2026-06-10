#if canImport(DougDomain)
    @testable import DougDomain
#else
    @testable import Doug
#endif
import Foundation
import Testing

struct StarterPeakEstimatorTests {
    let fedAt = Date(timeIntervalSince1970: 1_750_000_000)

    @Test func prefersActivationAverage() {
        let estimate = StarterPeakEstimator.estimatedPeakDate(
            feedTimestamp: fedAt,
            activePeakAverageMinutes: 300,
            averageTimeToPeakMinutes: 600,
            kitchenTempCelsius: 22,
            now: fedAt.addingTimeInterval(12 * 3600)
        )
        #expect(estimate == fedAt.addingTimeInterval(300 * 60))
    }

    @Test func fallsBackToOverallAverage() {
        let estimate = StarterPeakEstimator.estimatedPeakDate(
            feedTimestamp: fedAt,
            activePeakAverageMinutes: nil,
            averageTimeToPeakMinutes: 600,
            kitchenTempCelsius: 22,
            now: fedAt.addingTimeInterval(24 * 3600)
        )
        #expect(estimate == fedAt.addingTimeInterval(600 * 60))
    }

    @Test func fallsBackToTemperatureDefault() {
        let expected = TemperatureCalculator.levainBuildMinutes(kitchenTemp: 22)
        let estimate = StarterPeakEstimator.estimatedPeakDate(
            feedTimestamp: fedAt,
            activePeakAverageMinutes: nil,
            averageTimeToPeakMinutes: nil,
            kitchenTempCelsius: 22,
            now: fedAt.addingTimeInterval(48 * 3600)
        )
        #expect(estimate == fedAt.addingTimeInterval(expected * 60))
    }

    @Test func neverEstimatesInTheFuture() {
        let now = fedAt.addingTimeInterval(2 * 3600)
        let estimate = StarterPeakEstimator.estimatedPeakDate(
            feedTimestamp: fedAt,
            activePeakAverageMinutes: 600, // would land 10h after the feed
            averageTimeToPeakMinutes: nil,
            kitchenTempCelsius: 22,
            now: now
        )
        #expect(estimate == now)
    }

    @Test func neverEstimatesImplausiblySoonAfterFeed() {
        let estimate = StarterPeakEstimator.estimatedPeakDate(
            feedTimestamp: fedAt,
            activePeakAverageMinutes: 5, // implausibly fast average
            averageTimeToPeakMinutes: nil,
            kitchenTempCelsius: 22,
            now: fedAt.addingTimeInterval(12 * 3600)
        )
        let earliestPlausible = fedAt.addingTimeInterval(
            StarterPeakProfile.plausibleTimeToPeakRange.lowerBound * 60
        )
        #expect(estimate == earliestPlausible)
    }
}
