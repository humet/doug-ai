import Foundation

/// Generates a revival feeding plan for a neglected starter.
///
/// Creates a sequence of 3–4 consecutive feeds at a tight 1:2:2 ratio, spaced by expected
/// peak times that lengthen with neglect level. Respects the user's availability windows.
enum RevivalPlanGenerator {
    static let revivalRatio = (starter: 1, flour: 2, water: 2)

    /// Kitchen temperature at which the base `expectedPeakMinutes` values are calibrated.
    /// Deviations shrink or stretch peak times via `TemperatureCalculator.adjustedDuration`.
    static let referenceKitchenTempC = 22.0

    /// Expected peak time per revival feed, in minutes, at the reference kitchen
    /// temperature. Tuned per neglect level: mild starters pick up quickly; severe
    /// ones get an extra confirming feed.
    static func expectedPeakMinutes(for neglect: StarterNeglectLevel) -> [Double] {
        switch neglect {
        case .mild: [360, 300, 240] // 6h, 5h, 4h
        case .moderate: [480, 360, 300] // 8h, 6h, 5h
        case .severe: [600, 480, 360, 300] // 10h, 8h, 6h, 5h (4 feeds)
        }
    }

    /// Expected peak times adjusted for the user's actual kitchen temperature.
    /// Warmer kitchens shrink the wait; cooler kitchens stretch it.
    static func expectedPeakMinutes(
        for neglect: StarterNeglectLevel,
        kitchenTempC: Double
    ) -> [Double] {
        expectedPeakMinutes(for: neglect).map { base in
            TemperatureCalculator.adjustedDuration(
                baseDurationMinutes: base,
                referenceTemp: referenceKitchenTempC,
                actualTemp: kitchenTempC
            )
        }
    }

    /// Generates a revival plan with absolute gram amounts and tolerance bands.
    ///
    /// Retain grams stay constant across feeds (a small stable anchor is the common
    /// revival pattern); flour/water scale from the 1:2:2 ratio.
    static func generate(
        startTime: Date,
        initialStarterGrams: Double,
        neglect: StarterNeglectLevel,
        kitchenTempC: Double = referenceKitchenTempC,
        availability: AvailabilityInput,
        windows: [WindowInput],
        calendar: Calendar = .current
    ) -> [RevivalFeedPlan] {
        let peakSchedule = expectedPeakMinutes(for: neglect, kitchenTempC: kitchenTempC)
        let retainGrams = initialStarterGrams
        let addFlourGrams = retainGrams * Double(revivalRatio.flour) / Double(revivalRatio.starter)
        let addWaterGrams = retainGrams * Double(revivalRatio.water) / Double(revivalRatio.starter)

        var feeds: [RevivalFeedPlan] = []
        var cursor = startTime

        for (i, peakMinutes) in peakSchedule.enumerated() {
            let feedTime = FeedScheduler.snapToAvailableTime(
                candidate: cursor,
                availability: availability,
                windows: windows,
                calendar: calendar
            ) ?? cursor

            feeds.append(RevivalFeedPlan(
                sequenceIndex: i,
                scheduledTime: feedTime,
                expectedPeakMinutes: peakMinutes,
                minPeakMinutes: peakMinutes * 0.75,
                maxPeakMinutes: peakMinutes * 1.5,
                ratioStarter: revivalRatio.starter,
                ratioFlour: revivalRatio.flour,
                ratioWater: revivalRatio.water,
                retainStarterGrams: retainGrams,
                addFlourGrams: addFlourGrams,
                addWaterGrams: addWaterGrams
            ))

            // Next feed starts after expected peak + 30 min buffer
            cursor = feedTime.addingTimeInterval((peakMinutes + 30) * 60)
        }

        return feeds
    }

    /// Estimates when the starter will be bake-ready from the actual generated feed plan.
    /// Uses the last feed's scheduled time plus its expected peak, which accounts for
    /// availability snapping that the raw formula ignores.
    static func estimatedBakeReadyDate(from feeds: [RevivalFeedPlan]) -> Date? {
        guard let lastFeed = feeds.last else { return nil }
        return lastFeed.scheduledTime.addingTimeInterval(lastFeed.expectedPeakMinutes * 60)
    }

    /// Maps a step index to the instruction kind used for copy templates.
    static func stepKind(index: Int, totalSteps: Int) -> FeedStepKind {
        if index == 0 { return .revivalFirst }
        if index == totalSteps - 1 { return .revivalFinal }
        return .revivalMiddle
    }
}

/// A planned revival feed step (domain output, not SwiftData).
struct RevivalFeedPlan {
    let sequenceIndex: Int
    let scheduledTime: Date
    let expectedPeakMinutes: Double
    let minPeakMinutes: Double
    let maxPeakMinutes: Double
    let ratioStarter: Int
    let ratioFlour: Int
    let ratioWater: Int
    let retainStarterGrams: Double
    let addFlourGrams: Double
    let addWaterGrams: Double
}
