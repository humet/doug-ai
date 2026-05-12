import Foundation

enum RecipeBook {
    static let all: [Recipe] = [countryLoaf, highHydrationArtisan, wholeWheatHoney, oliveRosemary]

    static func recipe(for id: RecipeID) -> Recipe {
        guard let recipe = all.first(where: { $0.id == id }) else {
            fatalError("Unknown recipe ID: \(id.rawValue)")
        }
        return recipe
    }

    // MARK: - Country Loaf

    static let countryLoaf = Recipe(
        id: .countryLoaf,
        name: "Country Loaf",
        description: "The standard. 70% hydration, white bread flour, mild tang, open crumb. The recipe most users will start with.",
        difficulty: .beginner,
        hydrationPercent: 70,
        approximateTotalHours: 18 ... 26,
        ingredients: Ingredients(
            flourGrams: 500,
            waterGrams: 350,
            saltGrams: 10,
            levainGrams: 100
        ),
        method: [
            MethodStep(stepTypeID: .buildLevain),
            MethodStep(stepTypeID: .autolyse),
            MethodStep(stepTypeID: .mix),
            MethodStep(
                stepTypeID: .bulkFerment,
                durationOverrideMinutes: 240,
                foldCount: 4,
                degreeHourTarget: 80,
                foldSpacingFraction: 0.67
            ),
            MethodStep(stepTypeID: .shape),
            MethodStep(
                stepTypeID: .coldRetard,
                flexRangeOverride: 480 ... 1080
            ),
            MethodStep(stepTypeID: .preheat),
            MethodStep(stepTypeID: .bakeCovered, durationOverrideMinutes: 20),
            MethodStep(stepTypeID: .bakeUncovered, durationOverrideMinutes: 25),
        ],
        bakeTemperatureCelsius: 250,
        degreeHourTarget: 80,
        referenceTemperatureCelsius: 24.0
    )

    // MARK: - High Hydration Artisan

    static let highHydrationArtisan = Recipe(
        id: .highHydrationArtisan,
        name: "High Hydration Artisan",
        description: "80% hydration. Lacier crumb, more extensible dough, requires more confident handling. Longer bulk ferment and cold retard.",
        difficulty: .advanced,
        hydrationPercent: 80,
        approximateTotalHours: 20 ... 30,
        ingredients: Ingredients(
            flourGrams: 500,
            waterGrams: 400,
            saltGrams: 10,
            levainGrams: 100
        ),
        method: [
            MethodStep(stepTypeID: .buildLevain),
            MethodStep(stepTypeID: .autolyse, durationOverrideMinutes: 60),
            MethodStep(stepTypeID: .mix),
            MethodStep(
                stepTypeID: .bulkFerment,
                durationOverrideMinutes: 300,
                foldCount: 5,
                degreeHourTarget: 100,
                foldSpacingFraction: 0.70
            ),
            MethodStep(stepTypeID: .shape),
            MethodStep(
                stepTypeID: .coldRetard,
                flexRangeOverride: 600 ... 1080
            ),
            MethodStep(stepTypeID: .preheat),
            MethodStep(stepTypeID: .bakeCovered, durationOverrideMinutes: 20),
            MethodStep(stepTypeID: .bakeUncovered, durationOverrideMinutes: 25),
        ],
        bakeTemperatureCelsius: 250,
        degreeHourTarget: 100,
        referenceTemperatureCelsius: 24.0
    )

    // MARK: - Whole Wheat & Honey

    static let wholeWheatHoney = Recipe(
        id: .wholeWheatHoney,
        name: "Whole Wheat & Honey",
        description: "40% whole wheat flour, 68% hydration, with 30g honey. Denser crumb, slightly sweet, great for toast. Shorter bulk ferment.",
        difficulty: .intermediate,
        hydrationPercent: 68,
        approximateTotalHours: 16 ... 24,
        ingredients: Ingredients(
            flourGrams: 500,
            waterGrams: 340,
            saltGrams: 10,
            levainGrams: 125,
            extras: [
                ExtraIngredient("Honey", grams: 30),
            ]
        ),
        method: [
            MethodStep(stepTypeID: .buildLevain),
            MethodStep(stepTypeID: .autolyse),
            MethodStep(stepTypeID: .mix),
            MethodStep(
                stepTypeID: .bulkFerment,
                durationOverrideMinutes: 210,
                foldCount: 3,
                degreeHourTarget: 70,
                foldSpacingFraction: 0.67
            ),
            MethodStep(stepTypeID: .shape),
            MethodStep(
                stepTypeID: .coldRetard,
                flexRangeOverride: 480 ... 1080
            ),
            MethodStep(stepTypeID: .preheat),
            MethodStep(stepTypeID: .bakeCovered, durationOverrideMinutes: 20),
            MethodStep(stepTypeID: .bakeUncovered, durationOverrideMinutes: 25, bakeTemperatureCelsius: 230),
        ],
        bakeTemperatureCelsius: 245,
        degreeHourTarget: 70,
        referenceTemperatureCelsius: 24.0
    )

    // MARK: - Olive & Rosemary

    static let oliveRosemary = Recipe(
        id: .oliveRosemary,
        name: "Olive & Rosemary",
        description: "10% whole wheat, 69% hydration, with halved olives and fresh rosemary. Savoury, pairs well with soup and cheese.",
        difficulty: .intermediate,
        hydrationPercent: 69,
        approximateTotalHours: 18 ... 26,
        ingredients: Ingredients(
            flourGrams: 500,
            waterGrams: 345,
            saltGrams: 10,
            levainGrams: 100,
            extras: [
                ExtraIngredient("Olives", grams: 80, note: "halved"),
                ExtraIngredient("Fresh rosemary", grams: 5, note: "roughly chopped"),
            ]
        ),
        method: [
            MethodStep(stepTypeID: .buildLevain),
            MethodStep(stepTypeID: .autolyse),
            MethodStep(stepTypeID: .mix),
            MethodStep(
                stepTypeID: .bulkFerment,
                durationOverrideMinutes: 240,
                foldCount: 4,
                degreeHourTarget: 80,
                foldSpacingFraction: 0.67,
                inclusionAtFold: 2
            ),
            MethodStep(stepTypeID: .addInclusions),
            MethodStep(stepTypeID: .shape),
            MethodStep(
                stepTypeID: .coldRetard,
                flexRangeOverride: 480 ... 1080
            ),
            MethodStep(stepTypeID: .preheat),
            MethodStep(stepTypeID: .bakeCovered, durationOverrideMinutes: 20),
            MethodStep(stepTypeID: .bakeUncovered, durationOverrideMinutes: 25),
        ],
        bakeTemperatureCelsius: 250,
        degreeHourTarget: 80,
        referenceTemperatureCelsius: 24.0
    )
}
