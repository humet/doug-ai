#if canImport(DougDomain)
    @testable import DougDomain
#else
    @testable import Doug
#endif
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

    // MARK: - Outlier rejection

    @Test func implausibleReadingsAreExcludedFromBucket() {
        #expect(StarterPeakProfile.isPlausibleTimeToPeak(580))
        #expect(StarterPeakProfile.isPlausibleTimeToPeak(1423))
        #expect(!StarterPeakProfile.isPlausibleTimeToPeak(28720)) // ~20 days
        #expect(!StarterPeakProfile.isPlausibleTimeToPeak(-30)) // peak before feed
        #expect(!StarterPeakProfile.isPlausibleTimeToPeak(5)) // impossibly fast
    }

    /// Regression: the real-world feed history that made every bake show zero
    /// available start times. Three 1:5:5 cool-bracket activation feeds where one
    /// reading is a ~20-day logging artifact. The outlier must be dropped, leaving
    /// two samples — below threshold — so the scheduler falls back to a sane
    /// estimate instead of averaging the bucket up to ~7 days.
    @Test func twentyDayOutlierDoesNotPoisonBucket() {
        let profile = StarterPeakProfile(feedLogs: [
            Self.log(ratio: (1, 5, 5), temp: 20, timeToPeakMinutes: 772),
            Self.log(ratio: (1, 5, 5), temp: 20, timeToPeakMinutes: 1423),
            Self.log(ratio: (1, 5, 5), temp: 18, timeToPeakMinutes: 28720),
        ])

        // Without filtering this bucket would average (772+1423+28720)/3 ≈ 10,305 min.
        #expect(profile.sampleCount(ratio: .oneToFive, tempBracket: .cool) == 2)
        #expect(profile.averageMinutes(ratio: .oneToFive, tempBracket: .cool) == nil)
    }

    /// When enough plausible samples remain, the average reflects only them — the
    /// outlier never contributes.
    @Test func outlierExcludedFromOtherwiseValidAverage() {
        let profile = StarterPeakProfile(feedLogs: [
            Self.log(ratio: (1, 5, 5), temp: 20, timeToPeakMinutes: 600),
            Self.log(ratio: (1, 5, 5), temp: 20, timeToPeakMinutes: 700),
            Self.log(ratio: (1, 5, 5), temp: 20, timeToPeakMinutes: 800),
            Self.log(ratio: (1, 5, 5), temp: 18, timeToPeakMinutes: 28720),
        ])

        #expect(profile.sampleCount(ratio: .oneToFive, tempBracket: .cool) == 3)
        #expect(abs((profile.averageMinutes(ratio: .oneToFive, tempBracket: .cool) ?? 0) - 700) < 0.01)
    }

    // MARK: - Typical rise (display + diagnostic)

    @Test func typicalRiseMatchesCurrentTemperatureBracket() {
        let profile = StarterPeakProfile(feedLogs: [
            Self.log(ratio: (1, 5, 5), temp: 20, timeToPeakMinutes: 540),
            Self.log(ratio: (1, 5, 5), temp: 20, timeToPeakMinutes: 540),
            Self.log(ratio: (1, 5, 5), temp: 20, timeToPeakMinutes: 540),
        ])

        // Latest feed at 20°C → cool bracket, which has the data.
        #expect(
            profile.typicalRise(ratio: .oneToFive, nearTemperatureCelsius: 20)
                == .known(minutes: 540, bracket: .cool, matchesCurrentTemp: true)
        )
    }

    @Test func typicalRiseFallsBackToSampledBracketWhenCurrentTempHasNoData() {
        let profile = StarterPeakProfile(feedLogs: [
            Self.log(ratio: (1, 5, 5), temp: 20, timeToPeakMinutes: 540),
            Self.log(ratio: (1, 5, 5), temp: 20, timeToPeakMinutes: 540),
            Self.log(ratio: (1, 5, 5), temp: 20, timeToPeakMinutes: 540),
        ])

        // Current kitchen is warm (28°C) with no samples — fall back to the cool
        // bracket where the history actually lives, flagged as not-current.
        #expect(
            profile.typicalRise(ratio: .oneToFive, nearTemperatureCelsius: 28)
                == .known(minutes: 540, bracket: .cool, matchesCurrentTemp: false)
        )
    }

    @Test func typicalRisePicksMostSampledBracketWhenNoCurrentTemp() {
        let profile = StarterPeakProfile(feedLogs: [
            // cool: 3 samples
            Self.log(ratio: (1, 5, 5), temp: 20, timeToPeakMinutes: 600),
            Self.log(ratio: (1, 5, 5), temp: 20, timeToPeakMinutes: 600),
            Self.log(ratio: (1, 5, 5), temp: 20, timeToPeakMinutes: 600),
            // moderate: 4 samples — the most
            Self.log(ratio: (1, 5, 5), temp: 24, timeToPeakMinutes: 300),
            Self.log(ratio: (1, 5, 5), temp: 24, timeToPeakMinutes: 300),
            Self.log(ratio: (1, 5, 5), temp: 24, timeToPeakMinutes: 300),
            Self.log(ratio: (1, 5, 5), temp: 24, timeToPeakMinutes: 300),
        ])

        #expect(
            profile.typicalRise(ratio: .oneToFive, nearTemperatureCelsius: nil)
                == .known(minutes: 300, bracket: .moderate, matchesCurrentTemp: false)
        )
    }

    @Test func typicalRiseInsufficientDataBelowThreshold() {
        let profile = StarterPeakProfile(feedLogs: [
            Self.log(ratio: (1, 5, 5), temp: 20, timeToPeakMinutes: 540),
            Self.log(ratio: (1, 5, 5), temp: 20, timeToPeakMinutes: 540),
        ])

        #expect(profile.typicalRise(ratio: .oneToFive, nearTemperatureCelsius: 20) == .insufficientData)
    }

    /// The outlier filter and the typical-rise display compose: a 20-day reading
    /// is dropped, leaving too few samples, so the user sees "not enough data"
    /// rather than a poisoned "~7 days" figure.
    @Test func typicalRiseIgnoresOutlierAndReportsInsufficientData() {
        let profile = StarterPeakProfile(feedLogs: [
            Self.log(ratio: (1, 5, 5), temp: 20, timeToPeakMinutes: 772),
            Self.log(ratio: (1, 5, 5), temp: 20, timeToPeakMinutes: 1423),
            Self.log(ratio: (1, 5, 5), temp: 18, timeToPeakMinutes: 28720),
        ])

        #expect(profile.typicalRise(ratio: .oneToFive, nearTemperatureCelsius: 20) == .insufficientData)
    }

    @Test func unusuallyLongThresholdSeparatesNormalFromConcerning() {
        #expect(StarterPeakProfile.unusuallyLongRiseMinutes == 960) // 16h

        // A sluggish-but-plausible 18h average is reported as known and lands above
        // the concern threshold (the view renders the warning state).
        let profile = StarterPeakProfile(feedLogs: [
            Self.log(ratio: (1, 5, 5), temp: 20, timeToPeakMinutes: 1080),
            Self.log(ratio: (1, 5, 5), temp: 20, timeToPeakMinutes: 1080),
            Self.log(ratio: (1, 5, 5), temp: 20, timeToPeakMinutes: 1080),
        ])
        guard case let .known(minutes, _, _) =
            profile.typicalRise(ratio: .oneToFive, nearTemperatureCelsius: 20)
        else {
            Issue.record("Expected known rise"); return
        }
        #expect(minutes > StarterPeakProfile.unusuallyLongRiseMinutes)
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

        let levainWait = steps.first { $0.stepTypeID == .waitForLevainPeak }
        #expect(levainWait != nil)
        #expect(abs((levainWait?.durationMinutes ?? 0) - 210) < 1)
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

        let levainWait = steps.first { $0.stepTypeID == .waitForLevainPeak }
        #expect(levainWait != nil)
        #expect(abs((levainWait?.durationMinutes ?? 0) - 300) < 1)
    }

    /// Regression for the zero-available-times bug: a feed history containing a
    /// ~20-day outlier must not push the levain wait to days. The outlier is
    /// dropped, the bucket falls below threshold, and the build succeeds on the
    /// generic estimate rather than scheduling an impossible multi-day wait.
    @Test func outlierFeedHistoryDoesNotProduceMultiDayLevainWait() {
        func coolLog(_ minutes: Double, temp: Double = 20) -> FeedLogInput {
            FeedLogInput(
                timestamp: Date(),
                ratioStarter: 1,
                ratioFlour: 5,
                ratioWater: 5,
                flourType: "white",
                kitchenTemperatureCelsius: temp,
                timeToPeakMinutes: minutes,
                feedIntent: .activation
            )
        }
        let profile = StarterPeakProfile(
            feedLogs: [coolLog(772), coolLog(1423), coolLog(28720, temp: 18)],
            intentFilter: .activation
        )
        let input = ScheduleBuilderInput(
            recipe: RecipeBook.countryLoaf,
            targetBreadReadyTime: Self.targetTime(),
            kitchenTemperatureCelsius: 20.0,
            availability: Self.availability,
            peakProfile: profile
        )

        guard case let .success(steps) = ScheduleBuilder.build(input) else {
            Issue.record("Expected success"); return
        }

        let levainWait = steps.first { $0.stepTypeID == .waitForLevainPeak }
        #expect(levainWait != nil)
        // The poisoned average would have been ~10,305 min (~7 days). A sane
        // fallback is a handful of hours.
        #expect((levainWait?.durationMinutes ?? .infinity) < 1000)
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

        let levainWait = steps.first { $0.stepTypeID == .waitForLevainPeak }
        #expect(abs((levainWait?.durationMinutes ?? 0) - 300) < 1)
    }
}
