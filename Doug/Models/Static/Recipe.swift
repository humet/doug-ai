import Foundation

// MARK: - Recipe ID

enum RecipeID: String, CaseIterable, Codable {
    case countryLoaf
    case highHydrationArtisan
    case wholeWheatHoney
    case oliveRosemary
    case sameDayCountry
    case focaccia
    case pizzaDough
    case softRolls
}

// MARK: - Difficulty

enum Difficulty: String, Codable {
    case beginner
    case intermediate
    case advanced
}

// MARK: - Ingredients

struct Ingredients {
    let flourGrams: Double
    let waterGrams: Double
    let saltGrams: Double
    let levainGrams: Double
    let levainHydrationPercent: Double
    let extras: [ExtraIngredient]

    init(
        flourGrams: Double,
        waterGrams: Double,
        saltGrams: Double,
        levainGrams: Double,
        levainHydrationPercent: Double = 100,
        extras: [ExtraIngredient] = []
    ) {
        self.flourGrams = flourGrams
        self.waterGrams = waterGrams
        self.saltGrams = saltGrams
        self.levainGrams = levainGrams
        self.levainHydrationPercent = levainHydrationPercent
        self.extras = extras
    }
}

/// When an extra ingredient gets incorporated into the dough. Drives which
/// step's instructions mention it.
enum IngredientIncorporation: String {
    /// Worked in during the Mix step (enrichments like honey, oil, butter).
    case mix
    /// Folded in during bulk via the Add Inclusions step (olives, herbs, nuts).
    case fold
    /// Applied at/after shaping, before the bake (toppings like flaky salt).
    case topping
}

struct ExtraIngredient {
    let name: String
    let grams: Double
    let note: String?
    let incorporation: IngredientIncorporation

    init(_ name: String, grams: Double, note: String? = nil, incorporation: IngredientIncorporation = .mix) {
        self.name = name
        self.grams = grams
        self.note = note
        self.incorporation = incorporation
    }
}

// MARK: - Recipe

struct Recipe: Identifiable {
    let id: RecipeID
    let name: String
    let description: String
    let difficulty: Difficulty
    let hydrationPercent: Int
    let approximateTotalHours: ClosedRange<Int>
    let ingredients: Ingredients
    let method: [MethodStep]
    let bakeTemperatureCelsius: Int
    let degreeHourTarget: Double
    let referenceTemperatureCelsius: Double
    let completionLabel: String

    init(
        id: RecipeID,
        name: String,
        description: String,
        difficulty: Difficulty,
        hydrationPercent: Int,
        approximateTotalHours: ClosedRange<Int>,
        ingredients: Ingredients,
        method: [MethodStep],
        bakeTemperatureCelsius: Int,
        degreeHourTarget: Double,
        referenceTemperatureCelsius: Double,
        completionLabel: String = "Bread Ready"
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.difficulty = difficulty
        self.hydrationPercent = hydrationPercent
        self.approximateTotalHours = approximateTotalHours
        self.ingredients = ingredients
        self.method = method
        self.bakeTemperatureCelsius = bakeTemperatureCelsius
        self.degreeHourTarget = degreeHourTarget
        self.referenceTemperatureCelsius = referenceTemperatureCelsius
        self.completionLabel = completionLabel
    }

    func bakeTemperature(for stepTypeID: StepTypeID) -> Int {
        method.first { $0.stepTypeID == stepTypeID }?.bakeTemperatureCelsius ?? bakeTemperatureCelsius
    }

    var levainBuildRatio: (starter: Int, flour: Int, water: Int) {
        method.first { $0.stepTypeID == .buildLevain }?.levainBuildRatio ?? (1, 5, 5)
    }
}
