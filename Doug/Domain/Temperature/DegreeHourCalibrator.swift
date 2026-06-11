import Foundation

/// Refines per-recipe degree-hour targets based on completed bake profiles.
///
/// After enough bakes with logged outcomes, this replaces the recipe's default
/// target with a personalized value calibrated to the user's starter, flour,
/// and environment.
enum DegreeHourCalibrator {
    /// Minimum number of "good" bakes needed before refining the target.
    static let minimumBakes = 3

    /// Final degree-hours outside this multiple of the recipe default are
    /// treated as junk (abandoned bulk, mis-logged temps) and excluded —
    /// one outlier would otherwise drag the target for every future bake.
    static let plausibleTargetMultiplierRange = 0.5 ... 2.0

    /// The refined target is clamped to this multiple of the recipe default.
    /// History is a noisy signal (sparse readings, whole-loaf ratings standing
    /// in for bulk quality), so calibration may nudge the target but never
    /// yank it far from the recipe's tested value.
    static let refinedTargetClampMultiplierRange = 0.8 ... 1.2

    /// Returns a refined degree-hour target for a recipe based on historical
    /// fermentation profiles with favorable outcomes.
    ///
    /// - Parameters:
    ///   - recipeID: The recipe to calibrate.
    ///   - profiles: All completed bake fermentation profiles, in any order.
    /// - Returns: Refined target, or nil if insufficient data.
    static func refinedTarget(
        recipeID: RecipeID,
        profiles: [BakeProfileInput]
    ) -> Double? {
        let recipeDefault = RecipeBook.recipe(for: recipeID).degreeHourTarget
        let plausibleRange = (plausibleTargetMultiplierRange.lowerBound * recipeDefault)
            ... (plausibleTargetMultiplierRange.upperBound * recipeDefault)

        let goodBakes = profiles
            .filter {
                $0.recipeID == recipeID && $0.isGoodOutcome
                    && plausibleRange.contains($0.finalDegreeHours)
            }
            .sorted { $0.completedAt < $1.completedAt }
        guard goodBakes.count >= minimumBakes else { return nil }

        // Weighted average: more recent bakes weighted higher
        let count = Double(goodBakes.count)
        var weightedSum = 0.0
        var totalWeight = 0.0

        for (index, bake) in goodBakes.enumerated() {
            let weight = Double(index + 1) / count // linear ramp: 1/n, 2/n, ... 1.0
            weightedSum += bake.finalDegreeHours * weight
            totalWeight += weight
        }

        guard totalWeight > 0 else { return nil }
        let refined = weightedSum / totalWeight
        return min(
            max(refined, refinedTargetClampMultiplierRange.lowerBound * recipeDefault),
            refinedTargetClampMultiplierRange.upperBound * recipeDefault
        )
    }
}

/// Lightweight input for calibration, decoupled from SwiftData.
struct BakeProfileInput {
    let recipeID: RecipeID
    let finalDegreeHours: Double
    let completedAt: Date
    /// Reflection rating 1–5; 0 means unrated.
    let rating: Int
    let outcomeNote: String?

    var isGoodOutcome: Bool {
        // The rating is the explicit signal; the note-keyword scan is a
        // fallback for bakes finished before ratings existed.
        if rating > 0 { return rating >= 4 }
        guard let note = outcomeNote?.lowercased() else { return false }
        let positive = ["good", "great", "perfect", "excellent", "nice"]
        return positive.contains(where: { note.contains($0) })
    }
}
