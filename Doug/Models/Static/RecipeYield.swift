import Foundation

/// A selectable size for one unit of a recipe's yield, e.g. a 12" pizza ball.
struct YieldSizePreset: Identifiable, Equatable {
    let id: String
    let label: String
    let unitGrams: Double
}

/// What a recipe makes at its written quantities, and how far the user can
/// scale it at plan time. Scaling multiplies ingredient grams only — step
/// durations are unaffected.
struct RecipeYield {
    let unitSingular: String
    let unitPlural: String
    /// How many units the recipe's written ingredient amounts produce.
    let baseCount: Int
    /// Approximate dough grams per unit at the base quantities. Nil means the
    /// unit size is derived from total dough mass / `baseCount` and the user
    /// only scales by count.
    let approxUnitGrams: Double?
    /// Counts the user can choose at plan time.
    let countRange: ClosedRange<Int>
    /// Selectable unit sizes (pizza ball sizes). Empty for count-only recipes.
    let sizePresets: [YieldSizePreset]

    init(
        unitSingular: String = "loaf",
        unitPlural: String = "loaves",
        baseCount: Int = 1,
        approxUnitGrams: Double? = nil,
        countRange: ClosedRange<Int> = 1 ... 2,
        sizePresets: [YieldSizePreset] = []
    ) {
        self.unitSingular = unitSingular
        self.unitPlural = unitPlural
        self.baseCount = baseCount
        self.approxUnitGrams = approxUnitGrams
        self.countRange = countRange
        self.sizePresets = sizePresets
    }

    func unitName(for count: Int) -> String {
        count == 1 ? unitSingular : unitPlural
    }

    /// "Makes 3 × ~285g balls", "Makes 8 rolls", "Makes 1 loaf".
    var label: String {
        if let grams = approxUnitGrams {
            return "Makes \(baseCount) × ~\(Int(grams.rounded()))g \(unitName(for: baseCount))"
        }
        return "Makes \(baseCount) \(unitName(for: baseCount))"
    }
}
