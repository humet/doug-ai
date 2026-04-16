import Foundation

// MARK: - Recipe ID

enum RecipeID: String, CaseIterable, Codable, Sendable {
    case countryLoaf
    case highHydrationArtisan
    case wholeWheatHoney
    case oliveRosemary
}

// MARK: - Difficulty

enum Difficulty: String, Codable, Sendable {
    case beginner
    case intermediate
    case advanced
}

// MARK: - Ingredients

struct Ingredients: Sendable {
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

struct ExtraIngredient: Sendable {
    let name: String
    let grams: Double
    let note: String?

    init(_ name: String, grams: Double, note: String? = nil) {
        self.name = name
        self.grams = grams
        self.note = note
    }
}

// MARK: - Recipe

struct Recipe: Identifiable, Sendable {
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
}
