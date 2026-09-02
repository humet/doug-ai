#if canImport(DougDomain)
    @testable import DougDomain
#else
    @testable import Doug
#endif
import Foundation
import Testing

struct StarterEstablishProgressTests {
    private static func signals(
        bubbles: Bool = false,
        risen: Bool = false,
        doubled: Bool = false,
        smell: StarterSmell = .nothing
    ) -> StarterCheckInSignals {
        StarterCheckInSignals(hasBubbles: bubbles, hasRisen: risen, hasDoubled: doubled, smell: smell)
    }

    private static func evaluate(
        origin: StarterOrigin = .fromScratch,
        phase: StarterEstablishPhase,
        day: Int = 1,
        signals: StarterCheckInSignals,
        consecutiveDoubles: Int = 0
    ) -> EstablishOutcome {
        StarterEstablishProgress.evaluate(
            origin: origin,
            phase: phase,
            dayNumber: day,
            signals: signals,
            consecutiveDoubles: consecutiveDoubles
        )
    }

    // MARK: - Signals

    @Test func doublingImpliesRising() {
        let s = Self.signals(doubled: true)
        #expect(s.hasRisen)
    }

    @Test func onlyYeastySmellsCountAsEncouraging() {
        #expect(Self.signals(smell: .pleasantlySour).smellsEncouraging)
        #expect(Self.signals(smell: .yeastyBready).smellsEncouraging)
        #expect(!Self.signals(smell: .cheesyOrFunky).smellsEncouraging)
        #expect(!Self.signals(smell: .sharpVinegar).smellsEncouraging)
        #expect(!Self.signals(smell: .nothing).smellsEncouraging)
    }

    // MARK: - Initial Mix

    @Test func theOpeningMixNeverNamesTheNextPhaseItself() {
        // A dried culture has no once-a-day stage, and a from-scratch plan has
        // a second opening step. Naming a phase here would delete them.
        for origin in StarterOrigin.allCases {
            let outcome = Self.evaluate(origin: origin, phase: .initialMix, signals: Self.signals())
            #expect(outcome == .holdCourse, "\(origin) got \(outcome)")
        }
    }

    @Test func aFunkyEarlyRiseIsReportedAsAFalseRise() {
        let outcome = Self.evaluate(
            phase: .initialMix,
            day: 2,
            signals: Self.signals(bubbles: true, risen: true, smell: .cheesyOrFunky)
        )
        #expect(outcome == .falseRise)
    }

    // MARK: - False Rise

    @Test func theDayThreeBloomIsCaughtDuringDailyFeeds() {
        let outcome = Self.evaluate(
            phase: .dailyFeeds,
            day: 3,
            signals: Self.signals(bubbles: true, risen: true, smell: .cheesyOrFunky)
        )
        #expect(outcome == .falseRise)
    }

    @Test func aFunkySmellWithoutARiseIsNotAFalseRise() {
        // Smell alone isn't the bloom — the dramatic rise is what fools people.
        let outcome = Self.evaluate(
            phase: .dailyFeeds,
            day: 3,
            signals: Self.signals(bubbles: true, smell: .cheesyOrFunky)
        )
        #expect(outcome != .falseRise)
    }

    @Test func aPleasantRiseIsNotAFalseRise() {
        #expect(!StarterEstablishProgress.isFalseRise(
            Self.signals(bubbles: true, risen: true, smell: .pleasantlySour)
        ))
    }

    @Test func falseRiseNeverDerailsThePlan() {
        // The whole point: it's informational, so the plan must not advance,
        // stall, or complete off the back of it.
        let outcome = Self.evaluate(
            phase: .dailyFeeds,
            day: 3,
            signals: Self.signals(bubbles: true, risen: true, smell: .cheesyOrFunky)
        )
        #expect(outcome == .falseRise)
    }

    // MARK: - Advancing Early

    @Test func bubblesPlusAGoodSmellRampsUpEarly() {
        let outcome = Self.evaluate(
            phase: .dailyFeeds,
            day: 4,
            signals: Self.signals(bubbles: true, smell: .yeastyBready)
        )
        #expect(outcome == .advancePhase(.twiceDailyFeeds))
    }

    @Test func bubblesWithNoSmellHoldsCourse() {
        let outcome = Self.evaluate(
            phase: .dailyFeeds,
            day: 4,
            signals: Self.signals(bubbles: true, smell: .nothing)
        )
        #expect(outcome == .holdCourse)
    }

    @Test func aDoubleDuringTwiceDailyFeedsMovesToConfirming() {
        let outcome = Self.evaluate(
            phase: .twiceDailyFeeds,
            day: 6,
            signals: Self.signals(bubbles: true, doubled: true, smell: .pleasantlySour)
        )
        #expect(outcome == .advancePhase(.confirming))
    }

    // MARK: - Stalling

    @Test func noSignsByDaySevenIsStalledFromScratch() {
        let outcome = Self.evaluate(
            origin: .fromScratch,
            phase: .dailyFeeds,
            day: 7,
            signals: Self.signals()
        )
        guard case let .stalled(advice, extraFeeds) = outcome else {
            Issue.record("expected stalled, got \(outcome)")
            return
        }
        #expect(extraFeeds == 3)
        #expect(!advice.isEmpty)
    }

    @Test func aScratchStarterIsGivenPatienceBeforeDaySeven() {
        let outcome = Self.evaluate(
            origin: .fromScratch,
            phase: .dailyFeeds,
            day: 5,
            signals: Self.signals()
        )
        #expect(outcome == .holdCourse)
    }

    @Test func aDriedCultureIsExpectedToWakeSooner() {
        // Day five is patience for scratch and a stall for a culture that's
        // already alive.
        let scratch = Self.evaluate(origin: .fromScratch, phase: .dailyFeeds, day: 5, signals: Self.signals())
        let dried = Self.evaluate(origin: .driedCulture, phase: .dailyFeeds, day: 5, signals: Self.signals())

        #expect(scratch == .holdCourse)
        if case .stalled = dried {} else {
            Issue.record("expected dried culture to be stalled by day 5, got \(dried)")
        }
    }

    @Test func stallDayOrderingReflectsHowAliveTheCultureAlreadyIs() {
        #expect(
            StarterEstablishProgress.stallDay(for: .fromScratch)
                > StarterEstablishProgress.stallDay(for: .driedCulture)
        )
        #expect(
            StarterEstablishProgress.stallDay(for: .driedCulture)
                > StarterEstablishProgress.stallDay(for: .freshGift)
        )
    }

    @Test func anyVisibleActivityPreventsAStall() {
        let bubbling = Self.evaluate(phase: .dailyFeeds, day: 10, signals: Self.signals(bubbles: true))
        if case .stalled = bubbling {
            Issue.record("bubbles should never read as stalled")
        }

        let rising = Self.evaluate(phase: .dailyFeeds, day: 10, signals: Self.signals(risen: true))
        if case .stalled = rising {
            Issue.record("a rise should never read as stalled")
        }
    }

    @Test func stallAdviceIsRouteSpecific() {
        let scratch = StarterEstablishProgress.stallAdvice(for: .fromScratch)
        let dried = StarterEstablishProgress.stallAdvice(for: .driedCulture)
        let gift = StarterEstablishProgress.stallAdvice(for: .freshGift)

        #expect(scratch != dried)
        #expect(dried != gift)
        // Warmth is the single biggest lever, so every route should mention it.
        #expect(scratch.contains("26"))
        #expect(dried.contains("26"))
    }

    @Test func stallCanAlsoHappenDuringTwiceDailyFeeds() {
        let outcome = Self.evaluate(
            origin: .fromScratch,
            phase: .twiceDailyFeeds,
            day: 9,
            signals: Self.signals()
        )
        if case .stalled = outcome {} else {
            Issue.record("expected stalled, got \(outcome)")
        }
    }

    // MARK: - Confirming

    @Test func scratchNeedsTwoConsecutiveDoubles() {
        #expect(StarterEstablishProgress.requiredConsecutiveDoubles(for: .fromScratch) == 2)

        let first = Self.evaluate(
            phase: .confirming,
            signals: Self.signals(bubbles: true, doubled: true, smell: .pleasantlySour),
            consecutiveDoubles: 0
        )
        #expect(first == .holdCourse)

        let second = Self.evaluate(
            phase: .confirming,
            signals: Self.signals(bubbles: true, doubled: true, smell: .pleasantlySour),
            consecutiveDoubles: 1
        )
        #expect(second == .complete)
    }

    @Test func aLiveGiftedStarterOnlyHasToProveItselfOnce() {
        #expect(StarterEstablishProgress.requiredConsecutiveDoubles(for: .freshGift) == 1)

        let outcome = Self.evaluate(
            origin: .freshGift,
            phase: .confirming,
            signals: Self.signals(bubbles: true, doubled: true, smell: .pleasantlySour),
            consecutiveDoubles: 0
        )
        #expect(outcome == .complete)
    }

    @Test func aMissedConfirmingFeedAddsMoreConfirmingFeeds() {
        let outcome = Self.evaluate(
            phase: .confirming,
            signals: Self.signals(bubbles: true, risen: true, smell: .pleasantlySour),
            consecutiveDoubles: 1
        )
        #expect(outcome == .needsMoreConfirming(extraFeeds: 2))
    }

    @Test func aMissedConfirmingFeedDoesNotCompleteEvenWithPriorDoubles() {
        // Guards against an off-by-one that would let a near miss through.
        let outcome = Self.evaluate(
            phase: .confirming,
            signals: Self.signals(bubbles: true),
            consecutiveDoubles: 5
        )
        #expect(outcome != .complete)
    }

    // MARK: - Encoding

    @Test func signalsRoundTripThroughStorage() {
        let original = StarterCheckInSignals(
            hasBubbles: true, hasRisen: true, hasDoubled: false, smell: .cheesyOrFunky
        )
        guard let decoded = StarterCheckInSignals(encoded: original.encoded) else {
            Issue.record("failed to decode \(original.encoded)")
            return
        }
        #expect(decoded == original)
    }

    @Test func encodingStaysHumanReadable() {
        let encoded = StarterCheckInSignals(
            hasBubbles: true, hasRisen: false, hasDoubled: false, smell: .pleasantlySour
        ).encoded
        #expect(encoded.contains("bubbles:1"))
        #expect(encoded.contains("smell:pleasantlySour"))
    }

    @Test func garbageDecodesToNil() {
        #expect(StarterCheckInSignals(encoded: "") == nil)
        #expect(StarterCheckInSignals(encoded: "bubbles:1") == nil)
        #expect(StarterCheckInSignals(encoded: "smell:notARealSmell") == nil)
    }

    @Test func falseRiseExplanationNamesTheCauseAndTheCrash() {
        let text = StarterEstablishProgress.falseRiseExplanation
        #expect(text.contains("leuconostoc"))
        #expect(text.lowercased().contains("collapse"))
        #expect(text.lowercased().contains("don't start again"))
    }

    // MARK: - Activity Levels

    @Test func activityLevelsImplyTheOnesBeforeThem() {
        #expect(!StarterActivityLevel.nothing.hasBubbles)
        #expect(!StarterActivityLevel.nothing.hasRisen)

        #expect(StarterActivityLevel.bubbles.hasBubbles)
        #expect(!StarterActivityLevel.bubbles.hasRisen)

        #expect(StarterActivityLevel.rose.hasBubbles)
        #expect(StarterActivityLevel.rose.hasRisen)
        #expect(!StarterActivityLevel.rose.hasDoubled)

        #expect(StarterActivityLevel.doubled.hasBubbles)
        #expect(StarterActivityLevel.doubled.hasRisen)
        #expect(StarterActivityLevel.doubled.hasDoubled)
    }

    @Test func signalsCannotHoldAContradiction() {
        // Doubled-but-didn't-rise, and risen-but-no-bubbles, are impossible.
        let odd = StarterCheckInSignals(
            hasBubbles: false, hasRisen: false, hasDoubled: true, smell: .pleasantlySour
        )
        #expect(odd.hasRisen)
        #expect(odd.hasBubbles)
    }

    @Test func aRoseLevelWithAFunkySmellIsTheClassicFalseRise() {
        let signals = StarterCheckInSignals(activity: .rose, smell: .cheesyOrFunky)
        #expect(StarterEstablishProgress.isFalseRise(signals))
    }

    @Test func nothingSeenIsNeverAFalseRise() {
        for smell in StarterSmell.allCases {
            let signals = StarterCheckInSignals(activity: .nothing, smell: smell)
            #expect(!StarterEstablishProgress.isFalseRise(signals))
        }
    }

    @Test func everyOutcomeMapsToTheRightNotice() {
        #expect(EstablishOutcome.holdCourse.notice == nil)
        #expect(EstablishOutcome.falseRise.notice == .falseRise)
        #expect(EstablishOutcome.advancePhase(.confirming).notice == .advanced)
        #expect(EstablishOutcome.stalled(advice: "x", extraFeeds: 3).notice == .stalled)
        #expect(EstablishOutcome.needsMoreConfirming(extraFeeds: 2).notice == .needsMoreConfirming)
        #expect(EstablishOutcome.complete.notice == .complete)
    }
}
