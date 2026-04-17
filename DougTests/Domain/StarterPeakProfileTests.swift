@testable import Doug
import Foundation
import Testing

struct StarterPeakProfileTests {
    // MARK: - Helpers

    private static func log(
        ratio: (Int, Int, Int),
        temp: Double,
        timeToPeakMinutes: Double?,
        daysAgo: Double = 0
    ) -> FeedLogInput {
        FeedLogInput(
            timestamp: Date().addingTimeInterval(-daysAgo * 86400),
            ratioStarter: ratio.0,
            ratioFlour: ratio.1,
            ratioWater: ratio.2,
            flourType: "white",
            kitchenTemperatureCelsius: temp,
            timeToPeakMinutes: timeToPeakMinutes
        )
    }

    // MARK: - Ratio bucketing

    @Test func ratioBucketsNormaliseEquivalentFeeds() {
        #expect(FeedRatioBucket.bucket(starter: 1, flour: 5, water: 5) == .oneToFive)
        #expect(FeedRatioBucket.bucket(starter: 10, flour: 50, water: 50) == .oneToFive)
        #expect(FeedRatioBucket.bucket(starter: 1, flour: 1, water: 1) == .oneToOne)
        #expect(FeedRatioBucket.bucket(starter: 1, flour: 2, water: 2) == .oneToTwo)
        #expect(FeedRatioBucket.bucket(starter: 1, flour: 10, water: 10) == .oneToTen)
    }

    @Test func unequalFlourWaterIsUnbucketed() {
        #expect(FeedRatioBucket.bucket(starter: 1, flour: 5, water: 4) == nil)
    }

    // MARK: - Temperature bracketing

    @Test func temperatureBracketsSplitAtBoundaries() {
        #expect(TemperatureBracket.bracket(celsius: 18) == .cool)
        #expect(TemperatureBracket.bracket(celsius: 21.9) == .cool)
        #expect(TemperatureBracket.bracket(celsius: 22) == .moderate)
        #expect(TemperatureBracket.bracket(celsius: 25.5) == .moderate)
        #expect(TemperatureBracket.bracket(celsius: 26) == .warm)
        #expect(TemperatureBracket.bracket(celsius: 30) == .warm)
    }

    // MARK: - Averaging & minimum-sample threshold

    @Test func bucketWithThreeSamplesReturnsAverage() {
        let profile = StarterPeakProfile(feedLogs: [
            Self.log(ratio: (1, 5, 5), temp: 23, timeToPeakMinutes: 200),
            Self.log(ratio: (1, 5, 5), temp: 24, timeToPeakMinutes: 210),
            Self.log(ratio: (1, 5, 5), temp: 25, timeToPeakMinutes: 220),
        ])

        let avg = profile.averageMinutes(ratio: .oneToFive, tempBracket: .moderate)
        #expect(avg != nil)
        #expect(abs((avg ?? 0) - 210) < 0.01)
        #expect(profile.averageHours(ratio: .oneToFive, tempBracket: .moderate) == 3.5)
    }

    @Test func bucketBelowThresholdReturnsNil() {
        let profile = StarterPeakProfile(feedLogs: [
            Self.log(ratio: (1, 5, 5), temp: 23, timeToPeakMinutes: 200),
            Self.log(ratio: (1, 5, 5), temp: 24, timeToPeakMinutes: 210),
        ])

        #expect(profile.averageMinutes(ratio: .oneToFive, tempBracket: .moderate) == nil)
    }

    @Test func logsWithoutPeakTimeAreIgnored() {
        let profile = StarterPeakProfile(feedLogs: [
            Self.log(ratio: (1, 5, 5), temp: 23, timeToPeakMinutes: 200),
            Self.log(ratio: (1, 5, 5), temp: 24, timeToPeakMinutes: nil),
            Self.log(ratio: (1, 5, 5), temp: 25, timeToPeakMinutes: 220),
        ])

        // Only two valid samples — under threshold.
        #expect(profile.averageMinutes(ratio: .oneToFive, tempBracket: .moderate) == nil)
    }

    @Test func samplesSplitAcrossBucketsDoNotMix() {
        let profile = StarterPeakProfile(feedLogs: [
            // 3 samples in 1:5:5 moderate
            Self.log(ratio: (1, 5, 5), temp: 23, timeToPeakMinutes: 200),
            Self.log(ratio: (1, 5, 5), temp: 23, timeToPeakMinutes: 210),
            Self.log(ratio: (1, 5, 5), temp: 23, timeToPeakMinutes: 220),
            // 1 sample in 1:5:5 warm — should not pad the moderate bucket.
            Self.log(ratio: (1, 5, 5), temp: 28, timeToPeakMinutes: 150),
            // 2 samples in 1:1:1 moderate — under threshold.
            Self.log(ratio: (1, 1, 1), temp: 23, timeToPeakMinutes: 120),
            Self.log(ratio: (1, 1, 1), temp: 23, timeToPeakMinutes: 130),
        ])

        #expect(profile.averageMinutes(ratio: .oneToFive, tempBracket: .moderate) == 210)
        #expect(profile.averageMinutes(ratio: .oneToFive, tempBracket: .warm) == nil)
        #expect(profile.averageMinutes(ratio: .oneToOne, tempBracket: .moderate) == nil)
        #expect(profile.sampleCount(ratio: .oneToFive, tempBracket: .moderate) == 3)
        #expect(profile.sampleCount(ratio: .oneToOne, tempBracket: .moderate) == 2)
    }

    @Test func emptyLogsProduceEmptyProfile() {
        let profile = StarterPeakProfile(feedLogs: [])
        #expect(profile.averageMinutes(ratio: .oneToFive, tempBracket: .moderate) == nil)
    }
}

// MARK: - Schedule builder integration

struct ScheduleBuilderPeakProfileTests {
    private static let availability = AvailabilityInput(
        startHour: 6, startMinute: 30,
        endHour: 21, endMinute: 0
    )

    private static func targetTime() -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 4
        components.day = 19
        components.hour = 9
        components.minute = 0
        components.timeZone = TimeZone(identifier: "Europe/London")
        return Calendar.current.date(from: components)!
    }

    private static func profileAveraging(_ minutes: Double) -> StarterPeakProfile {
        let logs = (0 ..< 3).map { _ in
            FeedLogInput(
                timestamp: Date(),
                ratioStarter: 1,
                ratioFlour: 5,
                ratioWater: 5,
                flourType: "white",
                kitchenTemperatureCelsius: 23.0,
                timeToPeakMinutes: minutes
            )
        }
        return StarterPeakProfile(feedLogs: logs)
    }

    @Test func personalisedProfileReplacesGenericLevainEstimate() {
        let input = ScheduleBuilderInput(
            recipe: RecipeBook.countryLoaf,
            targetBreadReadyTime: Self.targetTime(),
            kitchenTemperatureCelsius: 23.0,
            availability: Self.availability,
            peakProfile: Self.profileAveraging(210)
        )

        guard case let .success(steps) = ScheduleBuilder.build(input) else {
            Issue.record("Expected success"); return
        }

        let levain = steps.first { $0.stepTypeID == .buildLevain }
        #expect(levain != nil)
        #expect(abs((levain?.durationMinutes ?? 0) - 210) < 1)
    }

    @Test func missingProfileFallsBackToGenericEstimate() {
        let input = ScheduleBuilderInput(
            recipe: RecipeBook.countryLoaf,
            targetBreadReadyTime: Self.targetTime(),
            kitchenTemperatureCelsius: 23.0,
            availability: Self.availability,
            peakProfile: nil
        )

        guard case let .success(steps) = ScheduleBuilder.build(input) else {
            Issue.record("Expected success"); return
        }

        let levain = steps.first { $0.stepTypeID == .buildLevain }
        #expect(levain != nil)
        // Moderate kitchen → generic 300-minute estimate.
        #expect(abs((levain?.durationMinutes ?? 0) - 300) < 1)
    }

    @Test func belowThresholdBucketFallsBackToGenericEstimate() {
        let twoSampleLogs = (0 ..< 2).map { _ in
            FeedLogInput(
                timestamp: Date(),
                ratioStarter: 1,
                ratioFlour: 5,
                ratioWater: 5,
                flourType: "white",
                kitchenTemperatureCelsius: 23.0,
                timeToPeakMinutes: 210
            )
        }
        let input = ScheduleBuilderInput(
            recipe: RecipeBook.countryLoaf,
            targetBreadReadyTime: Self.targetTime(),
            kitchenTemperatureCelsius: 23.0,
            availability: Self.availability,
            peakProfile: StarterPeakProfile(feedLogs: twoSampleLogs)
        )

        guard case let .success(steps) = ScheduleBuilder.build(input) else {
            Issue.record("Expected success"); return
        }

        let levain = steps.first { $0.stepTypeID == .buildLevain }
        #expect(abs((levain?.durationMinutes ?? 0) - 300) < 1)
    }
}
