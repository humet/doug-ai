import Foundation

/// The kind of feed being described, used to pick the right instruction template.
enum FeedStepKind {
    case revivalFirst
    case revivalMiddle
    case revivalFinal
    case maintenance
}

/// Everything the instruction renderer needs to produce human-readable copy.
struct FeedInstructionInput {
    let retainGrams: Double
    let addFlourGrams: Double
    let addWaterGrams: Double
    let flourType: String
    let kitchenTempC: Double
    let expectedPeakMinutes: Double
    let kind: FeedStepKind
    let hadHooch: Bool
    let neglect: StarterNeglectLevel?
}

/// Human-readable instructions for a single feed.
struct FeedInstruction {
    let title: String
    let steps: [String]
    let watchFor: String
    let expectedWait: String
    let peakGuidance: String
}

/// Offline fallback copy for every kind of feed.
///
/// When the AI coach fails or the user is offline, `FeedInstruction` comes from here.
/// Tests assert substring presence — the exact wording can be edited safely.
enum FeedInstructions {
    static func instruction(for input: FeedInstructionInput) -> FeedInstruction {
        switch input.kind {
        case .revivalFirst:
            revivalFirst(input)
        case .revivalMiddle:
            revivalMiddle(input)
        case .revivalFinal:
            revivalFinal(input)
        case .maintenance:
            maintenance(input)
        }
    }

    // MARK: - Revival

    private static func revivalFirst(_ input: FeedInstructionInput) -> FeedInstruction {
        var steps: [String] = []

        if input.hadHooch {
            steps
                .append(
                    "Pour off any dark liquid on top, or stir it in — both are fine. It's just alcohol from hungry yeast."
                )
        }

        steps
            .append("In a clean jar, keep \(gramString(input.retainGrams)) of your existing starter. Discard the rest.")
        steps
            .append(
                "Add \(gramString(input.addFlourGrams)) \(input.flourType) flour and \(gramString(input.addWaterGrams)) water at room temp (~27°C)."
            )
        steps.append("Stir until no dry flour remains; scrape down the sides.")
        steps.append("Cover loosely and rest at \(tempString(input.kitchenTempC)).")

        let watchFor: String
        let peakGuidance: String

        switch input.neglect ?? .mild {
        case .severe:
            watchFor = "Even some bubbles and a faint rise is a good sign this round. Full doubling may take another feed or two."
            peakGuidance = "Your starter may barely rise this round — that's normal after long neglect. Any bubbles at all, even small ones near the surface, count as progress. If activity slows or the expected time passes, you can move on."
        default:
            watchFor = "Domed top, bubbles throughout, roughly doubled in volume. Tangy smell, not sharp."
            peakGuidance = "Watch for a domed top with bubbles throughout. When it stops rising and starts to flatten or pull away from the jar, that's peak."
        }

        return FeedInstruction(
            title: "Feed 1 — wake it up",
            steps: steps,
            watchFor: watchFor,
            expectedWait: waitString(input.expectedPeakMinutes),
            peakGuidance: peakGuidance
        )
    }

    private static func revivalMiddle(_ input: FeedInstructionInput) -> FeedInstruction {
        FeedInstruction(
            title: "Feed \(input.neglect == .severe ? "2" : "2") — build consistency",
            steps: [
                "Discard down to \(gramString(input.retainGrams)) of active starter.",
                "Add \(gramString(input.addFlourGrams)) \(input.flourType) flour and \(gramString(input.addWaterGrams)) water.",
                "Mix, scrape, and mark the jar at the starter line.",
                "Cover loosely and rest.",
            ],
            watchFor: "Bubbles visible within 90 minutes, faster rise than last time.",
            expectedWait: waitString(input.expectedPeakMinutes),
            peakGuidance: "Bubbles should appear faster this time. Mark peak when the rise stalls — it should be quicker than last feed."
        )
    }

    private static func revivalFinal(_ input: FeedInstructionInput) -> FeedInstruction {
        FeedInstruction(
            title: "Final feed — confirm it's ready",
            steps: [
                "Discard to \(gramString(input.retainGrams)).",
                "Add \(gramString(input.addFlourGrams)) \(input.flourType) flour and \(gramString(input.addWaterGrams)) water.",
                "Mix and mark the starting line.",
            ],
            watchFor: "Reliable double in the expected window, glossy domed top. If it hits, you're bake-ready.",
            expectedWait: waitString(input.expectedPeakMinutes),
            peakGuidance: "This is the confirmation feed. Look for a reliable double within the expected window — glossy dome, bubbly throughout. That means you're bake-ready."
        )
    }

    // MARK: - Maintenance

    private static func maintenance(_ input: FeedInstructionInput) -> FeedInstruction {
        FeedInstruction(
            title: "How to feed",
            steps: [
                "Weigh \(gramString(input.retainGrams)) starter into a clean jar. Discard the rest.",
                "Add \(gramString(input.addFlourGrams)) \(input.flourType) flour and \(gramString(input.addWaterGrams)) water (~27°C).",
                "Stir until smooth; mark the starting height on the jar.",
                "Cover loosely. Expect peak in \(waitString(input.expectedPeakMinutes)) at \(tempString(input.kitchenTempC)).",
            ],
            watchFor: "Domed top, bubbles throughout, roughly doubled.",
            expectedWait: waitString(input.expectedPeakMinutes),
            peakGuidance: "Watch for a domed top with bubbles throughout. When it stops rising, that's peak."
        )
    }

    // MARK: - Formatters

    private static func gramString(_ grams: Double) -> String {
        let rounded = Int(grams.rounded())
        return "\(rounded) g"
    }

    private static func tempString(_ celsius: Double) -> String {
        "\(Int(celsius.rounded()))°C"
    }

    private static func waitString(_ minutes: Double) -> String {
        if minutes < 90 {
            return "~\(Int(minutes.rounded())) min"
        }
        let hours = minutes / 60
        if hours.truncatingRemainder(dividingBy: 1) < 0.1 || hours.truncatingRemainder(dividingBy: 1) > 0.9 {
            return "~\(Int(hours.rounded())) h"
        }
        return "~\(String(format: "%.1f", hours)) h"
    }
}
