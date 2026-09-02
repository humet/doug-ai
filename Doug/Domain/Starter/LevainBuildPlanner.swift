import Foundation

/// Chooses the levain build (inoculation ratio) that ripens to land *in its usable
/// window* exactly when the dough work begins.
///
/// A baker doesn't treat the levain peak as a knife-edge the calendar bends around;
/// they size the build to be ripe when they need it. A long gap before the mix is
/// the reason to build a *slow* overnight levain (low inoculation), not idle time to
/// strand a fast one. This planner is the domain home for that decision.
enum LevainBuildPlanner {
    /// Ratios from fastest (high inoculation) to slowest (overnight). The planner
    /// sorts by estimated peak regardless, so order here is just the default set.
    static let defaultCandidates: [FeedRatioBucket] = [.oneToOne, .oneToTwo, .oneToFive, .oneToTen]

    /// Peak at/after which a build reads as an "overnight" levain.
    static let overnightThresholdMinutes: Double = 7 * 60

    /// Longest we'll hold a peaked levain (chilled) before it's used. Beyond this a
    /// fresh build simply can't bridge the gap and the schedule shape is wrong.
    static let maxHoldMinutes: Double = 24 * 60

    enum Classification: String, Equatable {
        case standard
        case overnight
        /// Built as slow as we can, then held (chilled) to bridge a remaining gap.
        case holdAfterPeak
    }

    struct Choice: Equatable {
        let ratio: FeedRatioBucket
        /// Estimated minutes from build to peak for the chosen ratio.
        let peakMinutes: Double
        /// Minutes the levain is held past peak before use (0 unless `holdAfterPeak`).
        let holdMinutes: Double
        let classification: Classification
    }

    enum Outcome: Equatable {
        case build(Choice)
        /// The window is shorter than even the fastest levain can ripen — the
        /// bread-ready time is too soon. Caller should surface a conflict.
        case tooSoon
    }

    /// Estimated minutes from build to peak for one ratio, preferring the baker's
    /// observed history for that ratio/temperature bucket over the generic model.
    static func peakMinutes(
        ratio: FeedRatioBucket,
        kitchenTemp: Double,
        profile: StarterPeakProfile?
    ) -> Double {
        let bracket = TemperatureBracket.bracket(celsius: kitchenTemp)
        if let profile, let observed = profile.averageMinutes(ratio: ratio, tempBracket: bracket) {
            return observed
        }
        return TemperatureCalculator.levainPeakMinutes(ratio: ratio, kitchenTemp: kitchenTemp)
    }

    /// Selects a build for a window of `windowMinutes` between the earliest feasible
    /// build start and the consuming step (mix/autolyse).
    ///
    /// Picks the *slowest* candidate whose peak still lands within the window (ripe,
    /// not under-proofed at mix). If that ratio peaks more than the plateau before
    /// the window ends, the remaining gap is bridged by holding the levain.
    static func selectBuild(
        windowMinutes: Double,
        kitchenTemp: Double,
        profile: StarterPeakProfile?,
        candidateRatios: [FeedRatioBucket] = defaultCandidates
    ) -> Outcome {
        let plateau = TemperatureCalculator.levainPlateauMinutes

        // (ratio, peak) sorted fastest → slowest.
        let ranked = candidateRatios
            .map { (ratio: $0, peak: peakMinutes(ratio: $0, kitchenTemp: kitchenTemp, profile: profile)) }
            .sorted { $0.peak < $1.peak }

        guard let fastest = ranked.first else { return .tooSoon }

        // Even the fastest levain isn't ripe by the time the dough work starts.
        if fastest.peak > windowMinutes {
            return .tooSoon
        }

        // Slowest candidate that still peaks within the window (ripe, not under-proofed).
        let fitting = ranked.last { $0.peak <= windowMinutes } ?? fastest
        let holdRaw = windowMinutes - fitting.peak

        // Within the plateau → ripe at mix, no hold needed.
        if holdRaw <= plateau {
            return .build(Choice(
                ratio: fitting.ratio,
                peakMinutes: fitting.peak,
                holdMinutes: 0,
                classification: fitting.peak >= overnightThresholdMinutes ? .overnight : .standard
            ))
        }

        // The slowest build still peaks well before the mix — hold (chill) the
        // levain to bridge the rest. The hold absorbs everything past peak, so the
        // plateau is irrelevant here.
        let hold = min(holdRaw, maxHoldMinutes)
        return .build(Choice(
            ratio: fitting.ratio,
            peakMinutes: fitting.peak,
            holdMinutes: hold,
            classification: .holdAfterPeak
        ))
    }
}
