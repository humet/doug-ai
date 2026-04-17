import Foundation

/// Scales recipe ingredients proportionally to a target total dough weight.
enum RecipeScaler {
    /// Scales all ingredients proportionally.
    ///
    /// - Parameters:
    ///   - ingredients: The original recipe ingredients.
    ///   - targetTotalWeight: Desired total dough weight in grams.
    /// - Returns: Scaled ingredients.
    static func scale(
        ingredients: Ingredients,
        toTotalWeight targetTotalWeight: Double
    ) -> ScaledIngredients {
        let currentTotal = ingredients.flourGrams
            + ingredients.waterGrams
            + ingredients.saltGrams
            + ingredients.levainGrams
            + ingredients.extras.reduce(0) { $0 + $1.grams }

        guard currentTotal > 0 else {
            return ScaledIngredients(flour: 0, water: 0, salt: 0, levain: 0, extras: [])
        }

        let factor = targetTotalWeight / currentTotal

        return ScaledIngredients(
            flour: ingredients.flourGrams * factor,
            water: ingredients.waterGrams * factor,
            salt: ingredients.saltGrams * factor,
            levain: ingredients.levainGrams * factor,
            extras: ingredients.extras.map {
                ScaledExtra(name: $0.name, grams: $0.grams * factor, note: $0.note)
            }
        )
    }
}

struct ScaledIngredients {
    let flour: Double
    let water: Double
    let salt: Double
    let levain: Double
    let extras: [ScaledExtra]

    var total: Double {
        flour + water + salt + levain + extras.reduce(0) { $0 + $1.grams }
    }
}

struct ScaledExtra {
    let name: String
    let grams: Double
    let note: String?
}
