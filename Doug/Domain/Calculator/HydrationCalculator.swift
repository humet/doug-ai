import Foundation

/// Pure hydration and baker's percentage calculations.
enum HydrationCalculator {
    /// Calculates true hydration including levain's flour and water contribution.
    ///
    /// For a 100% hydration levain, the levain is half flour and half water.
    /// This function accounts for any levain hydration percentage.
    ///
    /// - Parameters:
    ///   - flourGrams: Main dough flour weight.
    ///   - waterGrams: Main dough water weight.
    ///   - levainGrams: Total levain weight.
    ///   - levainHydrationPercent: Levain hydration (e.g., 100 for 1:1 flour:water).
    /// - Returns: True hydration percentage.
    static func trueHydration(
        flourGrams: Double,
        waterGrams: Double,
        levainGrams: Double,
        levainHydrationPercent: Double
    ) -> Double {
        let levainFlour = levainGrams / (1 + levainHydrationPercent / 100)
        let levainWater = levainGrams - levainFlour
        let totalFlour = flourGrams + levainFlour
        let totalWater = waterGrams + levainWater
        guard totalFlour > 0 else { return 0 }
        return (totalWater / totalFlour) * 100
    }

    /// Calculates dough-only hydration (ignoring levain contribution).
    static func doughHydration(flourGrams: Double, waterGrams: Double) -> Double {
        guard flourGrams > 0 else { return 0 }
        return (waterGrams / flourGrams) * 100
    }

    /// Calculates baker's percentages for all ingredients.
    static func bakersPercentages(
        flourGrams: Double,
        waterGrams: Double,
        levainGrams: Double,
        saltGrams: Double,
        extras: [(name: String, grams: Double)] = []
    ) -> BakersPercentages {
        guard flourGrams > 0 else {
            return BakersPercentages(flour: 0, water: 0, levain: 0, salt: 0, extras: [])
        }
        return BakersPercentages(
            flour: 100,
            water: (waterGrams / flourGrams) * 100,
            levain: (levainGrams / flourGrams) * 100,
            salt: (saltGrams / flourGrams) * 100,
            extras: extras.map { ($0.name, ($0.grams / flourGrams) * 100) }
        )
    }
}

struct BakersPercentages: Sendable {
    let flour: Double
    let water: Double
    let levain: Double
    let salt: Double
    let extras: [(name: String, percent: Double)]
}
