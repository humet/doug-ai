import Foundation

/// Refines per-recipe degree-hour targets based on completed bake profiles.
///
/// After enough bakes with logged outcomes, this replaces the recipe's default
/// target with a personalized value calibrated to the user's starter, flour,
/// and environment.
enum DegreeHourCalibrator {
    /// Minimum number of "good" bakes needed before refining the target.
    static let minimumBakes = 3

    /// Returns a refined degree-hour target for a recipe based on historical
    /// fermentation profiles with favorable outcomes.
    ///
    /// - Parameters:
    ///   - recipeID: The recipe to calibrate.
    ///   - profiles: All completed bake fermentation profiles.
    /// - Returns: Refined target, or nil if insufficient data.
    static func refinedTarget(
        recipeID: RecipeID,
        profiles: [BakeProfileInput]
    ) -> Double? {
        let goodBakes = profiles.filter {
            $0.recipeID == recipeID && $0.isGoodOutcome
        }
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
        return weightedSum / totalWeight
    }
}

/// Lightweight input for calibration, decoupled from SwiftData.
struct BakeProfileInput: Sendable {
    let recipeID: RecipeID
    let finalDegreeHours: Double
    let outcomeNote: String?

    var isGoodOutcome: Bool {
        guard let note = outcomeNote?.lowercased() else { return false }
        let positive = ["good", "great", "perfect", "excellent", "nice"]
        return positive.contains(where: { note.contains($0) })
    }
}
