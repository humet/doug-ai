import Foundation

/// Scales a recipe's ingredient quantities to a user-chosen yield (count and,
/// for recipes with size presets, grams per unit). Ratios — hydration, salt
/// percentage, flour blend — are invariant under scaling, and step durations
/// never scale: fermentation time is independent of batch size at home
/// quantities.
enum RecipeScaler {
    /// Total dough mass: flour, water, salt, levain, and all extras.
    static func totalMass(_ ingredients: Ingredients) -> Double {
        ingredients.flourGrams
            + ingredients.waterGrams
            + ingredients.saltGrams
            + ingredients.levainGrams
            + ingredients.extras.reduce(0) { $0 + $1.grams }
    }

    /// The multiplier to apply to every ingredient for a chosen yield.
    ///
    /// With `unitGrams` (pizza size preset), the target dough mass is
    /// `count × unitGrams` against the recipe's base mass. Without it, units
    /// keep their recipe-defined size and the factor is `count / baseCount`.
    static func factor(
        count: Int,
        unitGrams: Double?,
        yield: RecipeYield,
        baseIngredients: Ingredients
    ) -> Double {
        if let unitGrams {
            let baseMass = totalMass(baseIngredients)
            guard baseMass > 0 else { return 1 }
            return Double(count) * unitGrams / baseMass
        }
        guard yield.baseCount > 0 else { return 1 }
        return Double(count) / Double(yield.baseCount)
    }

    /// Multiplies every gram quantity by `factor`. Percentages (flour blend,
    /// levain hydration) are unchanged.
    static func scaled(_ ingredients: Ingredients, by factor: Double) -> Ingredients {
        guard factor != 1 else { return ingredients }
        return Ingredients(
            flourGrams: ingredients.flourGrams * factor,
            waterGrams: ingredients.waterGrams * factor,
            saltGrams: ingredients.saltGrams * factor,
            levainGrams: ingredients.levainGrams * factor,
            levainHydrationPercent: ingredients.levainHydrationPercent,
            extras: ingredients.extras.map {
                ExtraIngredient($0.name, grams: $0.grams * factor, note: $0.note, incorporation: $0.incorporation)
            },
            flourComposition: ingredients.flourComposition
        )
    }
}
