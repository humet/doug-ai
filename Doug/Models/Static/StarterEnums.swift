import Foundation

enum StarterStorageType: String, Codable {
    case fridge
    case counter
}

enum StarterHealthStatus: String, Codable {
    case readyToBake
    case needsFeed
    case needsRevival
    /// A new starter is being built from scratch or from another culture.
    case establishing
}

enum StarterLifecycleState: String, Codable {
    case dormant
    case activating
    case active
    case reviving
    /// Working through a plan that creates a brand-new starter.
    case establishing
}

enum FeedIntent: String, Codable {
    case maintenance
    case activation
    case levain
    case postBake
}

// MARK: - Starting a New Starter

/// Where a brand-new starter comes from. Drives the shape and length of the plan.
enum StarterOrigin: String, Codable, CaseIterable, Identifiable {
    /// Flour and water only — the full wild-yeast capture.
    case fromScratch
    /// Freeze-dried or dehydrated culture (a friend's, or a gift).
    case driedCulture
    /// A live, active starter handed over in a jar.
    case freshGift
    /// A shop-bought or kit culture with its own packet instructions.
    case shopKit

    var id: String {
        rawValue
    }
}

/// The stage a new-starter plan is in. Phases advance on what the user reports
/// seeing, not purely on elapsed days.
enum StarterEstablishPhase: String, Codable {
    /// The very first mix (or rehydration) — nothing is expected to happen yet.
    case initialMix
    /// One feed a day while wild yeast establishes.
    case dailyFeeds
    /// Two feeds a day as it builds strength.
    case twiceDailyFeeds
    /// Confirming feeds that must double reliably before the starter is usable.
    case confirming

    /// Phases only ever move forwards, so they need an order to compare against.
    var sortOrder: Int {
        switch self {
        case .initialMix: 0
        case .dailyFeeds: 1
        case .twiceDailyFeeds: 2
        case .confirming: 3
        }
    }
}

/// What a single plan step actually asks the user to do. Distinguishes feeds
/// that expect a peak from early steps where nothing will rise yet.
enum StarterStepKind: String, Codable {
    /// A revival feed on an existing starter — the original behaviour.
    case revivalFeed
    /// Flour and water only, no starter retained.
    case initialMix
    /// Dried flakes into warm water to make a slurry.
    case rehydrate
    /// First feed of a live starter someone gave you, settling it into your flour.
    case activateGift
    /// Once-daily discard and feed. No peak expected.
    case dailyFeed
    /// Twice-daily feed. A peak is possible but not required.
    case twiceDailyFeed
    /// A feed that must double inside the expected window.
    case readinessTest

    /// Whether the step should ask the user to watch for and mark a peak.
    var expectsPeak: Bool {
        switch self {
        case .revivalFeed, .activateGift, .twiceDailyFeed, .readinessTest:
            true
        case .initialMix, .rehydrate, .dailyFeed:
            false
        }
    }
}

/// How far the starter got since the last feed. Ordered, because each level
/// implies the one before it.
enum StarterActivityLevel: String, Codable, CaseIterable, Identifiable {
    /// Flat and still.
    case nothing
    /// Bubbles, but no real rise.
    case bubbles
    /// Rose up the jar without quite doubling.
    case rose
    /// Doubled or more.
    case doubled

    var id: String {
        rawValue
    }

    var hasBubbles: Bool {
        self != .nothing
    }

    var hasRisen: Bool {
        self == .rose || self == .doubled
    }

    var hasDoubled: Bool {
        self == .doubled
    }
}

/// What the starter smells like — the most diagnostic signal a user can report,
/// and the one that separates a real yeast culture from an early bacterial bloom.
enum StarterSmell: String, Codable, CaseIterable, Identifiable {
    /// Smells of nothing much, or just wet flour.
    case nothing
    /// Cheesy, funky, vomit-like — the classic leuconostoc bloom.
    case cheesyOrFunky
    /// Yeasty, bready, beery.
    case yeastyBready
    /// Harsh vinegar or nail polish.
    case sharpVinegar
    /// Pleasantly tangy, like yoghurt or sourdough.
    case pleasantlySour

    var id: String {
        rawValue
    }
}
