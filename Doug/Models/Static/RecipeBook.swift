import Foundation

enum RecipeBook {
    static let all: [Recipe] = [
        countryLoaf, highHydrationArtisan, wholeWheatHoney, oliveRosemary,
        sameDayCountry, focaccia, pizzaDough, softRolls,
    ]

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
            MethodStep(stepTypeID: .buildLevain, levainBuildRatio: (1, 5, 5)),
            MethodStep(stepTypeID: .waitForLevainPeak),
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
            MethodStep(stepTypeID: .bake, durationOverrideMinutes: 45, subSteps: [
                MethodStep(stepTypeID: .bakeCovered, durationOverrideMinutes: 20),
                MethodStep(stepTypeID: .bakeUncovered, durationOverrideMinutes: 25),
            ]),
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
            MethodStep(stepTypeID: .buildLevain, levainBuildRatio: (1, 5, 5)),
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
            MethodStep(stepTypeID: .bake, durationOverrideMinutes: 45, subSteps: [
                MethodStep(stepTypeID: .bakeCovered, durationOverrideMinutes: 20),
                MethodStep(stepTypeID: .bakeUncovered, durationOverrideMinutes: 25),
            ]),
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
            ],
            flourComposition: [
                FlourComponent(.wholeWheat, percent: 40),
                FlourComponent(.whiteBread, percent: 60),
            ]
        ),
        method: [
            MethodStep(stepTypeID: .buildLevain, levainBuildRatio: (1, 5, 5)),
            MethodStep(stepTypeID: .waitForLevainPeak),
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
            MethodStep(stepTypeID: .bake, durationOverrideMinutes: 45, subSteps: [
                MethodStep(stepTypeID: .bakeCovered, durationOverrideMinutes: 20),
                MethodStep(stepTypeID: .bakeUncovered, durationOverrideMinutes: 25, bakeTemperatureCelsius: 230),
            ]),
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
                ExtraIngredient("Olives", grams: 80, note: "halved", incorporation: .fold),
                ExtraIngredient("Fresh rosemary", grams: 5, note: "roughly chopped", incorporation: .fold),
            ],
            flourComposition: [
                FlourComponent(.wholeWheat, percent: 10),
                FlourComponent(.whiteBread, percent: 90),
            ]
        ),
        method: [
            MethodStep(stepTypeID: .buildLevain, levainBuildRatio: (1, 5, 5)),
            MethodStep(stepTypeID: .waitForLevainPeak),
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
            MethodStep(stepTypeID: .bake, durationOverrideMinutes: 45, subSteps: [
                MethodStep(stepTypeID: .bakeCovered, durationOverrideMinutes: 20),
                MethodStep(stepTypeID: .bakeUncovered, durationOverrideMinutes: 25),
            ]),
        ],
        bakeTemperatureCelsius: 250,
        degreeHourTarget: 80,
        referenceTemperatureCelsius: 24.0
    )

    // MARK: - Same-Day Country Loaf

    static let sameDayCountry = Recipe(
        id: .sameDayCountry,
        name: "Same-Day Country Loaf",
        description: "The classic country loaf without an overnight retard. Build your levain at a higher ratio (1:2:2) so it peaks in about 3 hours, then straight into a full bulk ferment. Ready in 8–12 hours.",
        difficulty: .intermediate,
        hydrationPercent: 70,
        approximateTotalHours: 8 ... 12,
        ingredients: Ingredients(
            flourGrams: 500,
            waterGrams: 350,
            saltGrams: 10,
            levainGrams: 100
        ),
        method: [
            MethodStep(stepTypeID: .buildLevain, levainBuildRatio: (1, 2, 2)),
            MethodStep(stepTypeID: .waitForLevainPeak, durationOverrideMinutes: 180),
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
                stepTypeID: .finalProof,
                flexRangeOverride: 60 ... 180
            ),
            MethodStep(stepTypeID: .preheat),
            MethodStep(stepTypeID: .bake, durationOverrideMinutes: 45, subSteps: [
                MethodStep(stepTypeID: .bakeCovered, durationOverrideMinutes: 20),
                MethodStep(stepTypeID: .bakeUncovered, durationOverrideMinutes: 25),
            ]),
        ],
        bakeTemperatureCelsius: 250,
        degreeHourTarget: 80,
        referenceTemperatureCelsius: 24.0
    )

    // MARK: - Focaccia

    static let focaccia = Recipe(
        id: .focaccia,
        name: "Focaccia",
        description: "High hydration, olive oil enriched, baked on a sheet pan. No shaping stress — just stretch, dimple, and bake. A great first bake.",
        difficulty: .beginner,
        hydrationPercent: 78,
        approximateTotalHours: 8 ... 12,
        ingredients: Ingredients(
            flourGrams: 500,
            waterGrams: 390,
            saltGrams: 10,
            levainGrams: 100,
            extras: [
                ExtraIngredient("Olive oil", grams: 30, note: "plus more for the pan"),
                ExtraIngredient("Flaky salt", grams: 5, note: "for topping", incorporation: .topping),
            ]
        ),
        method: [
            MethodStep(stepTypeID: .buildLevain, levainBuildRatio: (1, 2, 2)),
            MethodStep(stepTypeID: .waitForLevainPeak, durationOverrideMinutes: 180),
            MethodStep(stepTypeID: .autolyse),
            MethodStep(stepTypeID: .mix),
            MethodStep(
                stepTypeID: .bulkFerment,
                durationOverrideMinutes: 240,
                foldCount: 4,
                degreeHourTarget: 80,
                foldSpacingFraction: 0.67
            ),
            MethodStep(stepTypeID: .panShape),
            MethodStep(
                stepTypeID: .finalProof,
                flexRangeOverride: 45 ... 120
            ),
            MethodStep(stepTypeID: .preheat),
            MethodStep(stepTypeID: .bakeSheet, durationOverrideMinutes: 25),
        ],
        bakeTemperatureCelsius: 220,
        degreeHourTarget: 80,
        referenceTemperatureCelsius: 24.0
    )

    // MARK: - Pizza Dough

    static let pizzaDough = Recipe(
        id: .pizzaDough,
        name: "Pizza Dough",
        description: "Sourdough pizza dough — 65% hydration with olive oil. Divide into balls and proof at room temperature. You handle the bake.",
        difficulty: .beginner,
        hydrationPercent: 65,
        approximateTotalHours: 7 ... 10,
        ingredients: Ingredients(
            flourGrams: 450,
            waterGrams: 293,
            saltGrams: 9,
            levainGrams: 90,
            extras: [
                ExtraIngredient("Olive oil", grams: 15),
            ]
        ),
        method: [
            MethodStep(stepTypeID: .buildLevain, levainBuildRatio: (1, 2, 2)),
            MethodStep(stepTypeID: .waitForLevainPeak, durationOverrideMinutes: 180),
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
                stepTypeID: .finalProof,
                flexRangeOverride: 60 ... 150
            ),
        ],
        bakeTemperatureCelsius: 0,
        degreeHourTarget: 70,
        referenceTemperatureCelsius: 24.0,
        completionLabel: "Dough Ready"
    )

    // MARK: - Soft Rolls

    static let softRolls = Recipe(
        id: .softRolls,
        name: "Soft Rolls",
        description: "Enriched sourdough rolls with butter for a soft, tender crumb. Shape into balls in the evening, cold retard overnight, and bake straight from the fridge in the morning. Makes 8 rolls.",
        difficulty: .intermediate,
        hydrationPercent: 62,
        approximateTotalHours: 18 ... 26,
        ingredients: Ingredients(
            flourGrams: 500,
            waterGrams: 310,
            saltGrams: 9,
            levainGrams: 100,
            extras: [
                ExtraIngredient("Butter", grams: 40, note: "softened"),
            ]
        ),
        method: [
            MethodStep(stepTypeID: .buildLevain, levainBuildRatio: (1, 5, 5)),
            MethodStep(stepTypeID: .waitForLevainPeak),
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
            MethodStep(stepTypeID: .bakeSheet, durationOverrideMinutes: 22),
        ],
        bakeTemperatureCelsius: 200,
        degreeHourTarget: 70,
        referenceTemperatureCelsius: 24.0
    )
}
