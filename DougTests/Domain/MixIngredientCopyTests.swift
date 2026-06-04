import Testing
@testable import DougDomain

/// Verifies that recipe extras worked in at the Mix step surface in the Mix
/// step's instruction and notification copy, while fold/topping extras don't.
struct MixIngredientCopyTests {
    @Test func mixInstructionNamesHoneyForWholeWheatHoney() {
        let recipe = RecipeBook.wholeWheatHoney
        let text = StepTypeRegistry.instructionText(for: .mix, storage: nil, recipe: recipe)
        #expect(text == "Add the levain, salt, and honey to the autolysed dough. Pinch and fold until fully incorporated. Take a dough temperature reading.")
    }

    @Test func mixNotificationNamesHoney() {
        let text = StepTypeRegistry.notificationText(for: .mix, recipe: RecipeBook.wholeWheatHoney)
        #expect(text.contains("honey"))
        #expect(text.hasPrefix("Time to mix —"))
    }

    @Test func mixInstructionNamesOilForPizzaAndButterForRolls() {
        #expect(StepTypeRegistry.instructionText(for: .mix, storage: nil, recipe: RecipeBook.pizzaDough)
            .contains("olive oil"))
        #expect(StepTypeRegistry.instructionText(for: .mix, storage: nil, recipe: RecipeBook.softRolls)
            .contains("butter"))
    }

    @Test func mixCopyUnchangedForRecipesWithoutMixExtras() {
        // Country Loaf has no extras — copy must match the registry default exactly.
        let withRecipe = StepTypeRegistry.instructionText(for: .mix, storage: nil, recipe: RecipeBook.countryLoaf)
        #expect(withRecipe == StepTypeRegistry.type(for: .mix).instructionText)
    }

    @Test func mixCopyExcludesFoldAndToppingExtras() {
        // Olive & Rosemary extras are folded in (handled by Add Inclusions), so the
        // Mix copy must not mention them.
        let olive = StepTypeRegistry.instructionText(for: .mix, storage: nil, recipe: RecipeBook.oliveRosemary)
        #expect(olive == StepTypeRegistry.type(for: .mix).instructionText)
        #expect(!olive.contains("olive"))
        #expect(!olive.contains("rosemary"))

        // Focaccia: olive oil is a mix-in but flaky salt is a topping.
        let focaccia = StepTypeRegistry.instructionText(for: .mix, storage: nil, recipe: RecipeBook.focaccia)
        #expect(focaccia.contains("olive oil"))
        #expect(!focaccia.contains("flaky salt"))
    }

    @Test func nonMixStepsIgnoreRecipeExtras() {
        // The recipe-aware overload must defer to the storage-aware copy for non-Mix steps.
        let shape = StepTypeRegistry.instructionText(for: .shape, storage: nil, recipe: RecipeBook.wholeWheatHoney)
        #expect(shape == StepTypeRegistry.instructionText(for: .shape, storage: nil))
    }
}
