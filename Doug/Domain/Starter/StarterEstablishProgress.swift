import Foundation

/// What the user reports seeing at a check-in. These four signals are all a
/// person can reliably judge by eye and nose, and together they separate a
/// genuine yeast culture from the bacterial bloom that fakes one early on.
struct StarterCheckInSignals: Equatable, Codable {
    let hasBubbles: Bool
    let hasRisen: Bool
    let hasDoubled: Bool
    let smell: StarterSmell

    init(hasBubbles: Bool, hasRisen: Bool, hasDoubled: Bool, smell: StarterSmell) {
        // Each level implies the one before it: doubling is a rise, and a rise
        // means bubbles. Normalise so no caller can record a contradiction.
        self.hasDoubled = hasDoubled
        self.hasRisen = hasRisen || hasDoubled
        self.hasBubbles = hasBubbles || self.hasRisen
        self.smell = smell
    }

    init(activity: StarterActivityLevel, smell: StarterSmell) {
        self.init(
            hasBubbles: activity.hasBubbles,
            hasRisen: activity.hasRisen,
            hasDoubled: activity.hasDoubled,
            smell: smell
        )
    }

    /// A smell that suggests yeast and lactic acid rather than the early
    /// leuconostoc bloom.
    var smellsEncouraging: Bool {
        smell == .yeastyBready || smell == .pleasantlySour
    }

    // MARK: - Persistence

    /// Compact, human-readable encoding — the same reasoning as storing enums
    /// as String rawValues: a value you can read straight out of the store.
    var encoded: String {
        "bubbles:\(hasBubbles ? 1 : 0),risen:\(hasRisen ? 1 : 0),doubled:\(hasDoubled ? 1 : 0),smell:\(smell.rawValue)"
    }

    init?(encoded: String) {
        var fields: [String: String] = [:]
        for pair in encoded.split(separator: ",") {
            let parts = pair.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { continue }
            fields[String(parts[0])] = String(parts[1])
        }
        guard let smellRaw = fields["smell"],
              let smell = StarterSmell(rawValue: smellRaw)
        else { return nil }

        self.init(
            hasBubbles: fields["bubbles"] == "1",
            hasRisen: fields["risen"] == "1",
            hasDoubled: fields["doubled"] == "1",
            smell: smell
        )
    }
}

/// The persisted, user-facing summary of what the last check-in changed.
/// Stored on the plan so the explanation survives navigation and relaunches.
enum EstablishNotice: String, Codable {
    case falseRise
    case advanced
    case stalled
    case needsMoreConfirming
    case complete
}

/// What should happen to the plan after a check-in.
enum EstablishOutcome: Equatable {
    /// Carry on with the plan as generated.
    case holdCourse
    /// The early bacterial bloom. Purely informational — the plan does not
    /// change, but the user badly needs to be told this is expected.
    case falseRise
    /// The starter is ahead of schedule; skip forward to this phase.
    case advancePhase(StarterEstablishPhase)
    /// Nothing is happening. Offer troubleshooting and add more feeds.
    case stalled(advice: String, extraFeeds: Int)
    /// A confirming feed missed its window; add more confirming feeds.
    case needsMoreConfirming(extraFeeds: Int)
    /// The starter is established and ready to bake with.
    case complete

    /// The notice worth showing the user, if any.
    var notice: EstablishNotice? {
        switch self {
        case .holdCourse: nil
        case .falseRise: .falseRise
        case .advancePhase: .advanced
        case .stalled: .stalled
        case .needsMoreConfirming: .needsMoreConfirming
        case .complete: .complete
        }
    }
}

/// Decides how a new-starter plan progresses from what the user reports seeing.
///
/// Timelines vary enormously — the same method can take five days in a warm
/// August kitchen and three weeks in a cold one — so the generated plan is only
/// a baseline. These rules move it forward, hold it, or stretch it based on
/// observation rather than the calendar.
enum StarterEstablishProgress {
    /// How many consecutive in-window doubles a starter must show before it is
    /// declared ready. A live starter someone handed over only has to prove it
    /// once; a culture built from flour and water has to prove it twice.
    static func requiredConsecutiveDoubles(for origin: StarterOrigin) -> Int {
        switch origin {
        case .freshGift: 1
        case .fromScratch, .driedCulture, .shopKit: 2
        }
    }

    /// The day after which a complete absence of bubbles counts as stalled
    /// rather than normal. Building from scratch earns far more patience than
    /// waking a culture that is already alive.
    static func stallDay(for origin: StarterOrigin) -> Int {
        switch origin {
        case .fromScratch: 7
        case .driedCulture, .shopKit: 4
        case .freshGift: 3
        }
    }

    static func evaluate(
        origin: StarterOrigin,
        phase: StarterEstablishPhase,
        dayNumber: Int,
        signals: StarterCheckInSignals,
        consecutiveDoubles: Int
    ) -> EstablishOutcome {
        switch phase {
        case .initialMix:
            // Nothing is expected to happen yet, so a false rise is the only
            // finding worth reporting. The plan simply moves to its next step —
            // which phase that is belongs to the plan, not to this rule.
            isFalseRise(signals) ? .falseRise : .holdCourse
        case .dailyFeeds:
            evaluateDailyFeeds(origin: origin, dayNumber: dayNumber, signals: signals)
        case .twiceDailyFeeds:
            evaluateTwiceDailyFeeds(origin: origin, dayNumber: dayNumber, signals: signals)
        case .confirming:
            evaluateConfirming(origin: origin, signals: signals, consecutiveDoubles: consecutiveDoubles)
        }
    }

    private static func evaluateDailyFeeds(
        origin: StarterOrigin,
        dayNumber: Int,
        signals: StarterCheckInSignals
    ) -> EstablishOutcome {
        if isFalseRise(signals) {
            return .falseRise
        }
        // Bubbles plus a yeasty or pleasantly sour smell means the yeast has
        // taken over from the bacteria. Ramp up early.
        if signals.hasBubbles, signals.smellsEncouraging {
            return .advancePhase(.twiceDailyFeeds)
        }
        if isStalled(origin: origin, dayNumber: dayNumber, signals: signals) {
            return .stalled(advice: stallAdvice(for: origin), extraFeeds: 3)
        }
        return .holdCourse
    }

    private static func evaluateTwiceDailyFeeds(
        origin: StarterOrigin,
        dayNumber: Int,
        signals: StarterCheckInSignals
    ) -> EstablishOutcome {
        if signals.hasDoubled {
            return .advancePhase(.confirming)
        }
        if isStalled(origin: origin, dayNumber: dayNumber, signals: signals) {
            return .stalled(advice: stallAdvice(for: origin), extraFeeds: 3)
        }
        return .holdCourse
    }

    private static func evaluateConfirming(
        origin: StarterOrigin,
        signals: StarterCheckInSignals,
        consecutiveDoubles: Int
    ) -> EstablishOutcome {
        guard signals.hasDoubled else {
            return .needsMoreConfirming(extraFeeds: 2)
        }
        let doubles = consecutiveDoubles + 1
        return doubles >= requiredConsecutiveDoubles(for: origin) ? .complete : .holdCourse
    }

    // MARK: - Signals

    /// The leuconostoc bloom: a vigorous early rise that smells cheesy, funky,
    /// or frankly like vomit. It is bacteria, not yeast, and it will crash.
    static func isFalseRise(_ signals: StarterCheckInSignals) -> Bool {
        signals.hasRisen && signals.smell == .cheesyOrFunky
    }

    private static func isStalled(
        origin: StarterOrigin,
        dayNumber: Int,
        signals: StarterCheckInSignals
    ) -> Bool {
        dayNumber >= stallDay(for: origin) && !signals.hasBubbles && !signals.hasRisen
    }

    // MARK: - Copy

    /// The false-rise explainer. Worth being emphatic about: an early bloom
    /// that then collapses is the single most common reason people throw away
    /// a starter that was on track.
    static let falseRiseExplanation = """
    That vigorous rise is almost certainly leuconostoc — a bacteria that blooms \
    early and smells cheesy or downright unpleasant. It isn't yeast, and it isn't \
    a problem. Over the next day or two it will collapse and go quiet, which feels \
    like failure but is actually the wild yeast taking over. Keep feeding on \
    schedule and don't start again.
    """

    static func stallAdvice(for origin: StarterOrigin) -> String {
        switch origin {
        case .fromScratch:
            """
            Nothing yet is common, and usually fixable:

            • Warmth matters most. Aim for 24–26°C — an oven with only the light on, \
            or a shelf above the fridge.
            • Switch to wholemeal or rye flour. Both carry far more wild yeast than white.
            • If your tap water is chlorinated, use filtered or bottled water.
            • Keep it thick. Weigh flour and water equally rather than measuring by volume.

            Three more feeds have been added to the plan.
            """
        case .driedCulture, .shopKit:
            """
            Dried cultures can be slow to wake up, especially in a cool kitchen:

            • Keep the jar at 24–26°C.
            • Feed with wholemeal or rye rather than white flour.
            • Use filtered or bottled water if yours is chlorinated.

            Three more feeds have been added — dried culture usually comes back \
            once it's warm enough.
            """
        case .freshGift:
            """
            A live starter should wake up quickly, so something is holding it back:

            • Check the temperature — below about 20°C it will barely move.
            • Ask what flour it was raised on. Switching flour can slow a starter \
            for a few feeds.
            • If it travelled or sat in a hot car, it may need reviving rather than \
            just feeding.

            Three more feeds have been added.
            """
        }
    }
}
