@testable import Doug
import Foundation
import Testing

struct DegreeHourCalculatorTests {
    // MARK: - Accumulation

    @Test func twoReadingsLinearInterpolation() {
        let start = Date()
        let oneHourLater = start.addingTimeInterval(3600)

        let readings: [(timestamp: Date, temperatureCelsius: Double)] = [
            (start, 24.0),
            (oneHourLater, 24.0),
        ]

        let result = DegreeHourCalculator.accumulatedDegreeHours(readings: readings)
        // (24 - 4) × 1 hour = 20 degree-hours
        #expect(abs(result - 20.0) < 0.01)
    }

    @Test func threeReadingsAccumulates() {
        let start = Date()
        let readings: [(timestamp: Date, temperatureCelsius: Double)] = [
            (start, 24.0),
            (start.addingTimeInterval(3600), 26.0),
            (start.addingTimeInterval(7200), 26.0),
        ]

        let result = DegreeHourCalculator.accumulatedDegreeHours(readings: readings)
        // Interval 1: avg 25°C, (25-4) × 1h = 21
        // Interval 2: avg 26°C, (26-4) × 1h = 22
        // Total: 43
        #expect(abs(result - 43.0) < 0.01)
    }

    @Test func singleReadingReturnsZero() {
        let readings: [(timestamp: Date, temperatureCelsius: Double)] = [
            (Date(), 24.0),
        ]
        #expect(DegreeHourCalculator.accumulatedDegreeHours(readings: readings) == 0)
    }

    @Test func belowBaseTemperatureContributesZero() {
        let start = Date()
        let readings: [(timestamp: Date, temperatureCelsius: Double)] = [
            (start, 2.0),
            (start.addingTimeInterval(3600), 3.0),
        ]

        let result = DegreeHourCalculator.accumulatedDegreeHours(readings: readings)
        // avg 2.5°C, which is below base 4°C → 0
        #expect(result == 0)
    }

    // MARK: - Estimation

    @Test func estimatesRemainingTime() throws {
        let remaining = DegreeHourCalculator.estimatedMinutesRemaining(
            currentDegreeHours: 60,
            targetDegreeHours: 80,
            latestTempCelsius: 24.0
        )
        // Need 20 more degree-hours at (24-4)=20 effective °C
        // 20 / 20 = 1 hour = 60 minutes
        #expect(remaining != nil)
        #expect(try abs(#require(remaining) - 60.0) < 0.01)
    }

    @Test func alreadyReachedTargetReturnsZero() {
        let remaining = DegreeHourCalculator.estimatedMinutesRemaining(
            currentDegreeHours: 85,
            targetDegreeHours: 80,
            latestTempCelsius: 24.0
        )
        #expect(remaining == 0)
    }

    @Test func tooLowTempReturnsNil() {
        let remaining = DegreeHourCalculator.estimatedMinutesRemaining(
            currentDegreeHours: 60,
            targetDegreeHours: 80,
            latestTempCelsius: 3.0
        )
        #expect(remaining == nil)
    }

    // MARK: - Progress

    @Test func progressFraction() {
        #expect(DegreeHourCalculator.progress(currentDegreeHours: 40, targetDegreeHours: 80) == 0.5)
        #expect(DegreeHourCalculator.progress(currentDegreeHours: 80, targetDegreeHours: 80) == 1.0)
        #expect(DegreeHourCalculator.progress(currentDegreeHours: 100, targetDegreeHours: 80) == 1.0)
    }
}
