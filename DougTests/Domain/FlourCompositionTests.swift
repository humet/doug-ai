import Testing
@testable import DougDomain

/// Verifies that recipes with a flour blend expose the correct per-flour gram
/// weights, and that single-flour recipes collapse to one "Flour" row.
struct FlourCompositionTests {
    @Test func wholeWheatHoneyIsFortyPercentWholeWheat() {
        let rows = RecipeBook.wholeWheatHoney.ingredients.flourBreakdownRows
        #expect(rows.count == 2)
        #expect(rows[0].name == "Whole wheat")
        #expect(rows[0].grams == 200) // 40% of 500
        #expect(rows[1].name == "White bread flour")
        #expect(rows[1].grams == 300) // 60% of 500
    }

    @Test func oliveRosemaryIsTenPercentWholeWheat() {
        let rows = RecipeBook.oliveRosemary.ingredients.flourBreakdownRows
        #expect(rows.count == 2)
        #expect(rows[0].name == "Whole wheat")
        #expect(rows[0].grams == 50) // 10% of 500
        #expect(rows[1].grams == 450) // 90% of 500
    }

    @Test func singleFlourRecipesShowOneFlourRow() {
        let rows = RecipeBook.countryLoaf.ingredients.flourBreakdownRows
        #expect(rows.count == 1)
        #expect(rows[0].name == "Flour")
        #expect(rows[0].grams == RecipeBook.countryLoaf.ingredients.flourGrams)
    }

    @Test func allRecipesHydrateFlourBeforeMix() {
        // Every built-in recipe autolyses, so the Mix step never re-introduces
        // flour or water.
        for recipe in RecipeBook.all {
            #expect(recipe.hydratesFlourBeforeMix, "\(recipe.name) should hydrate flour before mixing")
        }
    }

    @Test func blendPercentagesSumToTotalFlour() {
        for recipe in RecipeBook.all {
            let ing = recipe.ingredients
            let total = ing.flourBreakdownRows.reduce(0.0) { $0 + $1.grams }
            #expect(abs(total - ing.flourGrams) < 0.001, "\(recipe.name) flour rows must sum to total flour")
        }
    }
}
