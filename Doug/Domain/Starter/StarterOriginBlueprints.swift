import Foundation

/// Absolute weights for one feed.
struct FeedGrams: Equatable {
    let retain: Double
    let flour: Double
    let water: Double
}

/// Starter : flour : water, as bakers write it.
struct FeedRatio: Equatable {
    let starter: Int
    let flour: Int
    let water: Int
}

/// Timing shape for a step kind, shared by planning and extension.
struct StepShape: Equatable {
    /// Gap to the next step, in minutes at the reference temperature.
    let cadence: Double
    /// Expected time to peak at the reference temperature. Zero when no peak
    /// is expected.
    let peak: Double
    let minFactor: Double
    let maxFactor: Double
    /// Whether the gap to the next step stretches in a cold kitchen. A "feed
    /// once a day" rhythm does not — a day is a day. A wait for a slurry or a
    /// peak does.
    let cadenceIsTemperatureSensitive: Bool

    static func forKind(_ kind: StarterStepKind) -> StepShape {
        switch kind {
        case .initialMix:
            StepShape(cadence: 1440, peak: 0, minFactor: 0, maxFactor: 0, cadenceIsTemperatureSensitive: false)
        case .rehydrate:
            StepShape(cadence: 180, peak: 0, minFactor: 0, maxFactor: 0, cadenceIsTemperatureSensitive: true)
        case .dailyFeed:
            StepShape(cadence: 1440, peak: 0, minFactor: 0, maxFactor: 0, cadenceIsTemperatureSensitive: false)
        case .twiceDailyFeed:
            // Wide band: it may double in four hours or not at all yet.
            StepShape(cadence: 720, peak: 480, minFactor: 0.5, maxFactor: 2.0, cadenceIsTemperatureSensitive: false)
        case .activateGift, .readinessTest, .revivalFeed:
            // Must double in roughly four to eight hours to count.
            StepShape(cadence: 750, peak: 360, minFactor: 0.67, maxFactor: 1.33, cadenceIsTemperatureSensitive: true)
        }
    }
}

/// A plan step before it is placed on the clock.
struct StarterStepBlueprint {
    let kind: StarterStepKind
    let phase: StarterEstablishPhase
    let grams: FeedGrams
    let ratio: FeedRatio
    let cadenceOverride: Double?

    init(
        kind: StarterStepKind,
        phase: StarterEstablishPhase,
        grams: FeedGrams,
        ratio: FeedRatio,
        cadenceOverride: Double? = nil
    ) {
        self.kind = kind
        self.phase = phase
        self.grams = grams
        self.ratio = ratio
        self.cadenceOverride = cadenceOverride
    }

    var shape: StepShape {
        StepShape.forKind(kind)
    }

    var cadenceMinutes: Double {
        cadenceOverride ?? shape.cadence
    }
}

/// The baseline shape of each route to a new starter, before temperature and
/// availability are applied by `StarterOriginPlanner`.
enum StarterOriginBlueprints {
    static func blueprints(
        for origin: StarterOrigin,
        seedGrams: Double
    ) -> [StarterStepBlueprint] {
        switch origin {
        case .fromScratch: fromScratch(seedGrams: seedGrams)
        case .driedCulture, .shopKit: driedCulture(flakeGrams: seedGrams)
        case .freshGift: freshGift(giftGrams: seedGrams)
        }
    }

    /// Flour and water only. Day 1 mixes, days 2–4 feed once a day through the
    /// bacterial bloom and the lull that follows it, days 5–6 step up to twice a
    /// day, then two confirming feeds at a tighter ratio.
    private static func fromScratch(seedGrams: Double) -> [StarterStepBlueprint] {
        let base = max(seedGrams, 20)
        let even = FeedGrams(retain: base, flour: base, water: base)
        let oneToOne = FeedRatio(starter: 1, flour: 1, water: 1)

        var blueprints = [
            StarterStepBlueprint(
                kind: .initialMix, phase: .initialMix,
                grams: FeedGrams(retain: 0, flour: base, water: base),
                ratio: FeedRatio(starter: 0, flour: 1, water: 1)
            ),
        ]

        // Days 2–4: once a day at 1:1:1.
        blueprints += (0 ..< 3).map { _ in
            StarterStepBlueprint(kind: .dailyFeed, phase: .dailyFeeds, grams: even, ratio: oneToOne)
        }

        // Days 5–6: twice a day, still 1:1:1, as it builds strength.
        blueprints += (0 ..< 4).map { _ in
            StarterStepBlueprint(kind: .twiceDailyFeed, phase: .twiceDailyFeeds, grams: even, ratio: oneToOne)
        }

        // Confirming feeds at 1:2:2 — the ratio a healthy starter must handle.
        blueprints += (0 ..< 2).map { _ in
            StarterStepBlueprint(
                kind: .readinessTest, phase: .confirming,
                grams: FeedGrams(retain: base / 2, flour: base, water: base),
                ratio: FeedRatio(starter: 1, flour: 2, water: 2)
            )
        }

        return blueprints
    }

    /// Rehydrate the flakes into a slurry, thicken with flour, then two feeds
    /// and a pair of confirming feeds. Much shorter than from scratch — the
    /// culture already exists, it is only asleep.
    private static func driedCulture(flakeGrams: Double) -> [StarterStepBlueprint] {
        let flakes = max(flakeGrams, 2)
        // A slurry needs roughly five times the flake weight in water.
        let soakWater = flakes * 5
        let slurry = (flakes + soakWater).rounded()
        let feedBase = max(slurry, 25)
        let even = FeedGrams(retain: feedBase, flour: feedBase, water: feedBase)

        var blueprints = [
            StarterStepBlueprint(
                kind: .rehydrate, phase: .initialMix,
                grams: FeedGrams(retain: flakes, flour: 0, water: soakWater),
                ratio: FeedRatio(starter: 1, flour: 0, water: 5)
            ),
            StarterStepBlueprint(
                kind: .initialMix, phase: .initialMix,
                grams: FeedGrams(retain: slurry, flour: slurry, water: 0),
                ratio: FeedRatio(starter: 1, flour: 1, water: 0),
                // ~18 h, the middle of a 12–24 h window.
                cadenceOverride: 1080
            ),
        ]

        blueprints += (0 ..< 2).map { _ in
            StarterStepBlueprint(
                kind: .twiceDailyFeed, phase: .twiceDailyFeeds,
                grams: even, ratio: FeedRatio(starter: 1, flour: 1, water: 1)
            )
        }

        blueprints += (0 ..< 2).map { _ in
            StarterStepBlueprint(
                kind: .readinessTest, phase: .confirming,
                grams: FeedGrams(retain: feedBase / 2, flour: feedBase, water: feedBase),
                ratio: FeedRatio(starter: 1, flour: 2, water: 2)
            )
        }

        return blueprints
    }

    /// A live starter only needs to settle into your flour and your kitchen,
    /// then prove itself once.
    private static func freshGift(giftGrams: Double) -> [StarterStepBlueprint] {
        // Cap the working amount: a generous jar shouldn't mean 200 g of flour.
        let base = min(max(giftGrams, 10), 50)

        return [
            StarterStepBlueprint(
                kind: .activateGift, phase: .twiceDailyFeeds,
                grams: FeedGrams(retain: base, flour: base, water: base),
                ratio: FeedRatio(starter: 1, flour: 1, water: 1)
            ),
            StarterStepBlueprint(
                kind: .readinessTest, phase: .confirming,
                grams: FeedGrams(retain: base / 2, flour: base, water: base),
                ratio: FeedRatio(starter: 1, flour: 2, water: 2)
            ),
        ]
    }
}
