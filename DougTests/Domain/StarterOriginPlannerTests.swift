#if canImport(DougDomain)
    @testable import DougDomain
#else
    @testable import Doug
#endif
import Foundation
import Testing

struct StarterOriginPlannerTests {
    /// Wide availability so snapping doesn't move anything unless a test wants it to.
    private static let wideOpen = AvailabilityInput(
        startHour: 0, startMinute: 0, endHour: 23, endMinute: 59
    )

    private static func environment(
        tempC: Double = StarterOriginPlanner.referenceKitchenTempC,
        availability: AvailabilityInput = wideOpen,
        windows: [WindowInput] = []
    ) -> StarterPlanEnvironment {
        StarterPlanEnvironment(
            kitchenTempC: tempC,
            availability: availability,
            windows: windows,
            calendar: .current
        )
    }

    private static func plan(
        _ origin: StarterOrigin,
        seedGrams: Double? = nil,
        tempC: Double = StarterOriginPlanner.referenceKitchenTempC,
        availability: AvailabilityInput = wideOpen,
        windows: [WindowInput] = [],
        startTime: Date = Date()
    ) -> [StarterProgramStep] {
        StarterOriginPlanner.plan(StarterOriginPlanInput(
            origin: origin,
            startTime: startTime,
            seedGrams: seedGrams ?? StarterOriginPlanner.defaultSeedGrams(for: origin),
            environment: environment(tempC: tempC, availability: availability, windows: windows)
        ))
    }

    // MARK: - Shape

    @Test func everyRouteProducesSteps() {
        for origin in StarterOrigin.allCases {
            #expect(!Self.plan(origin).isEmpty, "\(origin) produced no steps")
        }
    }

    @Test func fromScratchIsLongerThanEveryOtherRoute() {
        let scratch = Self.plan(.fromScratch).count
        for origin in StarterOrigin.allCases where origin != .fromScratch {
            #expect(scratch > Self.plan(origin).count)
        }
    }

    @Test func fromScratchSpansAtLeastAWeek() {
        let steps = Self.plan(.fromScratch)
        #expect((steps.last?.dayNumber ?? 0) >= 7)
    }

    @Test func freshGiftIsReadyWithinTwoDays() {
        let steps = Self.plan(.freshGift)
        #expect((steps.last?.dayNumber ?? 0) <= 2)
    }

    @Test func shopKitFollowsTheDriedCultureShape() {
        let dried = Self.plan(.driedCulture, seedGrams: 5).map(\.kind)
        let kit = Self.plan(.shopKit, seedGrams: 5).map(\.kind)
        #expect(dried == kit)
    }

    // MARK: - Step Kinds and Phases

    @Test func firstScratchStepIsAnInitialMixThatRetainsNothing() {
        let first = Self.plan(.fromScratch, seedGrams: 50).first
        #expect(first?.kind == .initialMix)
        #expect(first?.retainStarterGrams == 0)
        #expect(first?.addFlourGrams == 50)
        #expect(first?.addWaterGrams == 50)
        #expect(first?.ratioStarter == 0)
    }

    @Test func driedCultureStartsByRehydratingInWaterOnly() {
        let first = Self.plan(.driedCulture, seedGrams: 5).first
        #expect(first?.kind == .rehydrate)
        #expect(first?.retainStarterGrams == 5)
        #expect(first?.addFlourGrams == 0)
        // Roughly five parts water to one of flakes.
        #expect(first?.addWaterGrams == 25)
    }

    @Test func everyRouteEndsOnAReadinessTest() {
        for origin in StarterOrigin.allCases {
            let last = Self.plan(origin).last
            #expect(last?.kind == .readinessTest, "\(origin) ended on \(String(describing: last?.kind))")
            #expect(last?.phase == .confirming)
        }
    }

    @Test func readinessTestsUseATighterRatio() {
        for origin in StarterOrigin.allCases {
            let tests = Self.plan(origin).filter { $0.kind == .readinessTest }
            #expect(!tests.isEmpty)
            for test in tests {
                #expect(test.ratioStarter == 1)
                #expect(test.ratioFlour == 2)
                #expect(test.ratioWater == 2)
            }
        }
    }

    @Test func earlyStepsExpectNoPeakAndConfirmingStepsDo() {
        let steps = Self.plan(.fromScratch)
        #expect(steps.first?.expectsPeak == false)
        #expect(steps.last?.expectsPeak == true)

        for step in steps where step.kind == .dailyFeed {
            #expect(!step.expectsPeak)
            // A step with no peak still needs an honest wait to display.
            #expect(step.expectedPeakMinutes > 0)
            #expect(step.minPeakMinutes == nil)
            #expect(step.maxPeakMinutes == nil)
        }
    }

    @Test func sequenceIndicesAreContiguousAndTimesMoveForward() {
        for origin in StarterOrigin.allCases {
            let steps = Self.plan(origin)
            #expect(steps.map(\.sequenceIndex) == Array(0 ..< steps.count))
            for (earlier, later) in zip(steps, steps.dropFirst()) {
                #expect(later.scheduledTime > earlier.scheduledTime)
            }
        }
    }

    @Test func dailyFeedsAreRoughlyADayApart() {
        let steps = Self.plan(.fromScratch)
        let dailies = steps.filter { $0.kind == .dailyFeed }
        guard let first = dailies.first, let second = dailies.dropFirst().first else {
            Issue.record("expected at least two daily feeds")
            return
        }
        let hours = second.scheduledTime.timeIntervalSince(first.scheduledTime) / 3600
        #expect(hours >= 20 && hours <= 28)
    }

    // MARK: - Temperature

    @Test func aColdKitchenStretchesPeakExpectations() {
        let warm = Self.plan(.freshGift, tempC: 26)
        let cold = Self.plan(.freshGift, tempC: 18)
        let warmPeak = warm.first?.expectedPeakMinutes ?? 0
        let coldPeak = cold.first?.expectedPeakMinutes ?? 0
        #expect(coldPeak > warmPeak)
    }

    @Test func aDailyFeedRhythmDoesNotStretchWithTemperature() {
        // A day is a day, however cold the kitchen.
        let warm = Self.plan(.fromScratch, tempC: 27).filter { $0.kind == .dailyFeed }
        let cold = Self.plan(.fromScratch, tempC: 17).filter { $0.kind == .dailyFeed }
        #expect(warm.first?.expectedPeakMinutes == cold.first?.expectedPeakMinutes)
    }

    // MARK: - Availability

    @Test func feedsAfterTheFirstLandInsideAvailableHours() {
        let availability = AvailabilityInput(startHour: 8, startMinute: 0, endHour: 20, endMinute: 0)
        let calendar = Calendar.current
        let start = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date()

        let steps = Self.plan(
            .fromScratch,
            availability: availability,
            startTime: start
        )

        for step in steps.dropFirst() {
            let hour = calendar.component(.hour, from: step.scheduledTime)
            #expect(hour >= 8 && hour < 20, "step \(step.sequenceIndex) scheduled at \(hour):00")
        }
    }

    @Test func theFirstStepHappensWhenTheUserSaysItDoes() {
        // Even outside available hours — they're holding the jar right now.
        let availability = AvailabilityInput(startHour: 8, startMinute: 0, endHour: 20, endMinute: 0)
        let calendar = Calendar.current
        let start = calendar.date(bySettingHour: 23, minute: 30, second: 0, of: Date()) ?? Date()

        let steps = Self.plan(.driedCulture, availability: availability, startTime: start)
        #expect(steps.first?.scheduledTime == start)
    }

    // MARK: - Ready Date

    @Test func estimatedReadyDateFollowsTheFinalStep() {
        let steps = Self.plan(.driedCulture)
        guard let last = steps.last,
              let ready = StarterOriginPlanner.estimatedReadyDate(from: steps)
        else {
            Issue.record("expected a ready date")
            return
        }
        #expect(ready > last.scheduledTime)
        #expect(ready == last.scheduledTime.addingTimeInterval(last.expectedPeakMinutes * 60))
    }

    @Test func noStepsMeansNoReadyDate() {
        #expect(StarterOriginPlanner.estimatedReadyDate(from: []) == nil)
    }

    // MARK: - Extensions

    @Test func extensionStepsContinueFromTheTemplate() {
        let steps = Self.plan(.driedCulture)
        guard let last = steps.last else {
            Issue.record("expected steps")
            return
        }
        let startingAt = last.scheduledTime.addingTimeInterval(6 * 3600)

        let extra = StarterOriginPlanner.extensionSteps(
            StarterPlanExtension(
                template: last,
                count: 2,
                startingAt: startingAt,
                planStartDate: steps[0].scheduledTime
            ),
            environment: Self.environment()
        )

        #expect(extra.count == 2)
        #expect(extra.map(\.sequenceIndex) == [last.sequenceIndex + 1, last.sequenceIndex + 2])
        // Grams and ratio are inherited so an extension feeds it identically.
        #expect(extra[0].retainStarterGrams == last.retainStarterGrams)
        #expect(extra[0].addFlourGrams == last.addFlourGrams)
        #expect(extra[0].ratioFlour == last.ratioFlour)
        #expect(extra[0].kind == last.kind)
        #expect(extra[0].scheduledTime >= startingAt)
    }

    @Test func extensionCanChangeKindAndPhase() {
        let steps = Self.plan(.fromScratch)
        guard let daily = steps.first(where: { $0.kind == .dailyFeed }) else {
            Issue.record("expected a daily feed")
            return
        }

        let extra = StarterOriginPlanner.extensionSteps(
            StarterPlanExtension(
                template: daily,
                count: 3,
                startingAt: daily.scheduledTime.addingTimeInterval(86400),
                planStartDate: steps[0].scheduledTime,
                kind: .twiceDailyFeed,
                phase: .twiceDailyFeeds
            ),
            environment: Self.environment()
        )

        #expect(extra.count == 3)
        #expect(extra.allSatisfy { $0.kind == .twiceDailyFeed })
        #expect(extra.allSatisfy { $0.phase == .twiceDailyFeeds })
        #expect(extra.allSatisfy { $0.expectsPeak })
    }

    @Test func zeroCountExtensionProducesNothing() {
        let steps = Self.plan(.freshGift)
        let extra = StarterOriginPlanner.extensionSteps(
            StarterPlanExtension(
                template: steps[0],
                count: 0,
                startingAt: Date(),
                planStartDate: Date()
            ),
            environment: Self.environment()
        )
        #expect(extra.isEmpty)
    }

    // MARK: - Day Numbers

    @Test func dayNumberCountsTheStartDayAsOne() {
        let calendar = Calendar.current
        let start = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: Date()) ?? Date()
        #expect(StarterOriginPlanner.dayNumber(of: start, planStart: start) == 1)

        let sameDayLater = calendar.date(bySettingHour: 23, minute: 0, second: 0, of: start) ?? start
        #expect(StarterOriginPlanner.dayNumber(of: sameDayLater, planStart: start) == 1)

        let nextDay = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        #expect(StarterOriginPlanner.dayNumber(of: nextDay, planStart: start) == 2)
    }

    @Test func dayNumberNeverGoesBelowOne() {
        let start = Date()
        let before = start.addingTimeInterval(-3 * 86400)
        #expect(StarterOriginPlanner.dayNumber(of: before, planStart: start) == 1)
    }

    // MARK: - Route Metadata

    @Test func estimatedDaysAreHonestlyOrdered() {
        let scratch = StarterOriginPlanner.estimatedDays(for: .fromScratch)
        let dried = StarterOriginPlanner.estimatedDays(for: .driedCulture)
        let gift = StarterOriginPlanner.estimatedDays(for: .freshGift)

        #expect(scratch.lowerBound > dried.lowerBound)
        #expect(dried.lowerBound > gift.lowerBound)
        #expect(scratch.upperBound > dried.upperBound)
    }

    @Test func wholegrainFlourIsRecommendedForANewCulture() {
        // Wholemeal and rye carry far more wild yeast than white.
        #expect(StarterOriginPlanner.recommendedFlour(for: .fromScratch) != "white")
        #expect(StarterOriginPlanner.recommendedFlour(for: .driedCulture) != "white")
    }

    @Test func seedGramsHaveASensibleFloor() {
        // A tiny or absurd input shouldn't produce a nonsense plan.
        let tiny = Self.plan(.fromScratch, seedGrams: 1)
        #expect((tiny.first?.addFlourGrams ?? 0) >= 20)

        let huge = Self.plan(.freshGift, seedGrams: 500)
        // A generous jar shouldn't mean half a kilo of flour per feed.
        #expect((huge.first?.addFlourGrams ?? 0) <= 50)
    }
}
