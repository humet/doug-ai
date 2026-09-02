import Foundation

extension StarterStepKind {
    /// The instruction template that describes this step.
    var feedStepKind: FeedStepKind {
        switch self {
        case .revivalFeed: .revivalMiddle
        case .initialMix: .initialMix
        case .rehydrate: .rehydrate
        case .activateGift: .activateGift
        case .dailyFeed: .dailyFeed
        case .twiceDailyFeed: .twiceDailyFeed
        case .readinessTest: .readinessTest
        }
    }
}

/// Offline copy for the steps that build a brand-new starter.
///
/// Two things this copy has to get right, because they are where people give
/// up: the first days when nothing appears to happen, and the day-three
/// bacterial bloom that looks like triumph and then collapses.
extension FeedInstructions {
    static func newStarter(_ input: FeedInstructionInput) -> FeedInstruction {
        switch input.kind {
        case .rehydrate: rehydrate(input)
        case .initialMix: initialMix(input)
        case .dailyFeed: dailyFeed(input)
        case .twiceDailyFeed: twiceDailyFeed(input)
        case .activateGift: activateGift(input)
        case .readinessTest: readinessTest(input)
        default: initialMix(input)
        }
    }

    // MARK: - First Steps

    private static func rehydrate(_ input: FeedInstructionInput) -> FeedInstruction {
        FeedInstruction(
            title: "Wake the dried culture",
            steps: [
                "Tip \(gramString(input.retainGrams)) of the dried culture into a clean jar.",
                "Add \(gramString(input.addWaterGrams)) water at about 30°C — warm to the touch, never hot. "
                    + "Hot water kills the culture you're trying to save.",
                "Stir, cover loosely, and leave it to soften into a slurry.",
            ],
            watchFor: "The flakes soften and break down into a smooth slurry. "
                + "A few bubbles are a good sign; none yet is equally normal.",
            expectedWait: waitString(input.expectedPeakMinutes),
            peakGuidance: "Nothing to catch here — you're only softening the flakes. "
                + "Tap the button when you've mixed it."
        )
    }

    private static func initialMix(_ input: FeedInstructionInput) -> FeedInstruction {
        // A dried culture's first mix thickens an existing slurry; a from-scratch
        // starter's first mix is flour and water and nothing else.
        if input.retainGrams > 0 {
            return FeedInstruction(
                title: "Thicken it with flour",
                steps: [
                    "Stir \(gramString(input.addFlourGrams)) \(input.flourType) flour into your slurry.",
                    "Mix to a thick paste — no dry flour left.",
                    "Cover loosely and leave at \(tempString(input.kitchenTempC)).",
                ],
                watchFor: "Bubbles forming through the paste, and a rise up the jar. "
                    + "This is the step where a dried culture usually shows its first real signs of life.",
                expectedWait: waitString(input.expectedPeakMinutes),
                peakGuidance: "No peak to mark yet. Note what you see at the next feed."
            )
        }

        return FeedInstruction(
            title: "Day 1 — mix your first jar",
            steps: [
                "In a clean jar, mix \(gramString(input.addFlourGrams)) \(input.flourType) flour with "
                    + "\(gramString(input.addWaterGrams)) water at ~\(tempString(input.kitchenTempC)).",
                "Stir to a thick paste. Scrape down the sides so nothing dries out.",
                "Cover loosely — a lid resting on top, or a cloth and a band. It needs air, not a seal.",
                "Leave it somewhere warm, ideally \(tempString(input.kitchenTempC)) or a little above.",
            ],
            watchFor: "Almost certainly nothing. Day one is flour and water getting acquainted — "
                + "there is no yeast population yet to make anything happen.",
            expectedWait: waitString(input.expectedPeakMinutes),
            peakGuidance: "There's no peak to catch yet. Come back tomorrow and feed it."
        )
    }

    // MARK: - Daily Feeds

    private static func dailyFeed(_ input: FeedInstructionInput) -> FeedInstruction {
        let day = input.dayNumber
        let title = day.map { "Day \($0) — feed it" } ?? "Feed it"

        return FeedInstruction(
            title: title,
            steps: [
                "Discard all but \(gramString(input.retainGrams)). This feels wasteful and is not — "
                    + "you're concentrating the yeast, not throwing it away.",
                "Add \(gramString(input.addFlourGrams)) \(input.flourType) flour and "
                    + "\(gramString(input.addWaterGrams)) water at ~\(tempString(input.kitchenTempC)).",
                "Stir, scrape the sides, and mark the level on the jar with a rubber band or tape.",
                "Cover loosely and leave it warm.",
            ],
            watchFor: watchForDailyFeed(day: day),
            expectedWait: waitString(input.expectedPeakMinutes),
            peakGuidance: "No peak to mark at this stage. Just tell us what you see at the next feed — "
                + "bubbles, rise, and smell are what decide how the plan goes from here."
        )
    }

    /// Days two to four are when the leuconostoc bloom shows up. Naming it in
    /// advance is the difference between a user who keeps going and one who
    /// tips the jar out.
    private static func watchForDailyFeed(day: Int?) -> String {
        guard let day else {
            return "Bubbles, a faint rise, and a smell shifting from raw flour towards something sour."
        }

        switch day {
        case ..<3:
            return "Maybe a few bubbles, maybe nothing at all. Both are on track this early."
        case 3 ... 5:
            return "This is often when a starter puffs up dramatically and smells cheesy, funky, "
                + "or frankly awful. That's bacteria rather than yeast — expected, harmless, and it will pass. "
                + "Tell us if you see it."
        default:
            return "Bubbles through the mix and a smell moving towards yoghurt or beer. "
                + "If it went quiet after an early puff-up, that's the handover to wild yeast — keep feeding."
        }
    }

    private static func twiceDailyFeed(_ input: FeedInstructionInput) -> FeedInstruction {
        FeedInstruction(
            title: "Feed — twice a day now",
            steps: [
                "Discard down to \(gramString(input.retainGrams)).",
                "Add \(gramString(input.addFlourGrams)) \(input.flourType) flour and "
                    + "\(gramString(input.addWaterGrams)) water at ~\(tempString(input.kitchenTempC)).",
                "Stir and mark the level. Feeding twice a day builds strength fast from here.",
            ],
            watchFor: "Rising and falling on a predictable rhythm. It may double, it may fall a little short — "
                + "either is normal at this stage.",
            expectedWait: waitString(input.expectedPeakMinutes),
            peakGuidance: "If it domes and roughly doubles, mark the peak — that's real progress. "
                + "If it doesn't quite get there, feed again on schedule and try the next one."
        )
    }

    private static func activateGift(_ input: FeedInstructionInput) -> FeedInstruction {
        FeedInstruction(
            title: "Settle it into your kitchen",
            steps: [
                "Weigh \(gramString(input.retainGrams)) of the starter you were given into a clean jar.",
                "Add \(gramString(input.addFlourGrams)) \(input.flourType) flour and "
                    + "\(gramString(input.addWaterGrams)) water at ~\(tempString(input.kitchenTempC)).",
                "Stir until smooth and mark the starting level.",
                "Leave it on the counter at \(tempString(input.kitchenTempC)).",
            ],
            watchFor: "A live starter should bubble within a few hours and dome up. "
                + "Moving to new flour and a new kitchen can slow it for a feed or two — don't read that as a problem.",
            expectedWait: waitString(input.expectedPeakMinutes),
            peakGuidance: "Mark the peak when the dome stops rising and just begins to flatten."
        )
    }

    private static func readinessTest(_ input: FeedInstructionInput) -> FeedInstruction {
        FeedInstruction(
            title: "Confirming feed",
            steps: [
                "Discard down to \(gramString(input.retainGrams)).",
                "Add \(gramString(input.addFlourGrams)) \(input.flourType) flour and "
                    + "\(gramString(input.addWaterGrams)) water at ~\(tempString(input.kitchenTempC)).",
                "Stir and mark the starting level carefully — this feed is the test.",
            ],
            watchFor: "A clean double within about \(waitString(input.expectedPeakMinutes)), a domed top, "
                + "and a smell like tangy yoghurt rather than harsh vinegar.",
            expectedWait: waitString(input.expectedPeakMinutes),
            peakGuidance: "Mark the peak when the rise stalls. Doubling inside the window is what counts — "
                + "do it twice in a row and your starter is ready to bake with."
        )
    }
}
