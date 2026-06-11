#if canImport(DougDomain)
    @testable import DougDomain
#else
    @testable import Doug
#endif
import Testing

struct RecipeScalerTests {
    // MARK: - totalMass

    @Test func totalMassSumsAllIngredientsIncludingExtras() {
        // Pizza: 450 + 293 + 9 + 90 + 15 = 857
        #expect(RecipeScaler.totalMass(RecipeBook.pizzaDough.ingredients) == 857)
    }

    @Test func totalMassWithoutExtras() {
        // Country loaf: 500 + 350 + 10 + 100 = 960
        #expect(RecipeScaler.totalMass(RecipeBook.countryLoaf.ingredients) == 960)
    }

    // MARK: - scaled

    @Test func scalingByTwoDoublesEveryGramIncludingExtras() {
        let base = RecipeBook.pizzaDough.ingredients
        let scaled = RecipeScaler.scaled(base, by: 2)
        #expect(scaled.flourGrams == base.flourGrams * 2)
        #expect(scaled.waterGrams == base.waterGrams * 2)
        #expect(scaled.saltGrams == base.saltGrams * 2)
        #expect(scaled.levainGrams == base.levainGrams * 2)
        #expect(scaled.extras.count == base.extras.count)
        for (original, doubled) in zip(base.extras, scaled.extras) {
            #expect(doubled.grams == original.grams * 2)
            #expect(doubled.name == original.name)
            #expect(doubled.incorporation == original.incorporation)
        }
    }

    @Test func scalingPreservesHydrationAndSaltPercent() {
        let base = RecipeBook.highHydrationArtisan.ingredients
        let scaled = RecipeScaler.scaled(base, by: 1.7)
        #expect(abs(scaled.waterGrams / scaled.flourGrams - base.waterGrams / base.flourGrams) < 0.0001)
        #expect(abs(scaled.saltGrams / scaled.flourGrams - base.saltGrams / base.flourGrams) < 0.0001)
        let baseTrue = HydrationCalculator.trueHydration(
            flourGrams: base.flourGrams, waterGrams: base.waterGrams,
            levainGrams: base.levainGrams, levainHydrationPercent: base.levainHydrationPercent
        )
        let scaledTrue = HydrationCalculator.trueHydration(
            flourGrams: scaled.flourGrams, waterGrams: scaled.waterGrams,
            levainGrams: scaled.levainGrams, levainHydrationPercent: scaled.levainHydrationPercent
        )
        #expect(abs(baseTrue - scaledTrue) < 0.0001)
    }

    @Test func scalingLeavesPercentagesAndBlendUntouched() {
        let base = RecipeBook.wholeWheatHoney.ingredients
        let scaled = RecipeScaler.scaled(base, by: 2)
        #expect(scaled.levainHydrationPercent == base.levainHydrationPercent)
        #expect(scaled.flourComposition.count == base.flourComposition.count)
        for (original, copy) in zip(base.flourComposition, scaled.flourComposition) {
            #expect(copy.percent == original.percent)
            #expect(copy.type == original.type)
        }
    }

    @Test func identityFactorReturnsSameValues() {
        let base = RecipeBook.countryLoaf.ingredients
        let scaled = RecipeScaler.scaled(base, by: 1)
        #expect(scaled.flourGrams == base.flourGrams)
        #expect(scaled.levainGrams == base.levainGrams)
    }

    // MARK: - factor

    @Test func pizzaFactorFromCountAndBallWeight() {
        let recipe = RecipeBook.pizzaDough
        // 4 × 270g = 1080g against 857g base
        let factor = RecipeScaler.factor(
            count: 4, unitGrams: 270, yield: recipe.yield, baseIngredients: recipe.ingredients
        )
        #expect(abs(factor - 1080.0 / 857.0) < 0.0001)
    }

    @Test func factorWithoutUnitGramsIsCountOverBaseCount() {
        let recipe = RecipeBook.softRolls
        let factor = RecipeScaler.factor(
            count: 12, unitGrams: nil, yield: recipe.yield, baseIngredients: recipe.ingredients
        )
        #expect(abs(factor - 1.5) < 0.0001)
    }

    @Test func factorIsIdentityAtBaseYield() {
        let recipe = RecipeBook.countryLoaf
        let factor = RecipeScaler.factor(
            count: recipe.yield.baseCount, unitGrams: nil,
            yield: recipe.yield, baseIngredients: recipe.ingredients
        )
        #expect(factor == 1)
    }
}

struct RecipeYieldTests {
    @Test func everyRecipeHasAValidYield() {
        for recipe in RecipeBook.all {
            #expect(recipe.yield.baseCount >= 1)
            #expect(recipe.yield.countRange.contains(recipe.yield.baseCount))
            #expect(!recipe.yield.unitSingular.isEmpty)
            #expect(!recipe.yield.unitPlural.isEmpty)
        }
    }

    @Test func pizzaYieldMatchesItsDoughMass() {
        let yield = RecipeBook.pizzaDough.yield
        #expect(!yield.sizePresets.isEmpty)
        let impliedMass = Double(yield.baseCount) * (yield.approxUnitGrams ?? 0)
        let actualMass = RecipeScaler.totalMass(RecipeBook.pizzaDough.ingredients)
        // Stated yield (3 × ~285g) should be within 10% of the real dough mass.
        #expect(abs(impliedMass - actualMass) / actualMass < 0.1)
    }

    @Test func yieldLabels() {
        #expect(RecipeBook.pizzaDough.yield.label == "Makes 3 × ~285g balls")
        #expect(RecipeBook.countryLoaf.yield.label == "Makes 1 loaf")
        #expect(RecipeBook.softRolls.yield.label == "Makes 8 rolls")
    }
}

struct PizzaColdRetardMethodTests {
    @Test func pizzaMethodEndsShapeRetardTemper() {
        let ids = RecipeBook.pizzaDough.method.map(\.stepTypeID)
        #expect(ids.suffix(3) == [.shape, .coldRetardBalls, .temper])
        #expect(!ids.contains(.finalProof))
        #expect(!ids.contains(.preheat))
        #expect(!ids.contains(.bake))
    }

    @Test func ballRetardAndTemperRegistryEntries() {
        let retard = StepTypeRegistry.type(for: .coldRetardBalls)
        #expect(retard.classification == .passiveFlexible)
        #expect(retard.flexRange == 720 ... 4320)
        #expect(retard.instructionText.contains("balls"))

        let temper = StepTypeRegistry.type(for: .temper)
        #expect(temper.classification == .passiveFlexible)
        #expect(temper.flexRange == 60 ... 120)
        #expect(temper.instructionText.contains("room temperature"))
    }

    @Test func pizzaShapeCopyTalksBallsNotBanneton() {
        let text = StepTypeRegistry.instructionText(for: .shape, storage: nil, recipe: RecipeBook.pizzaDough)
        #expect(text.contains("balls"))
        #expect(!text.contains("banneton"))
        // Bread shape copy untouched.
        let bread = StepTypeRegistry.instructionText(for: .shape, storage: nil, recipe: RecipeBook.countryLoaf)
        #expect(bread.contains("banneton"))
    }

    @Test func bothRetardTypesDetectedAsColdRetard() {
        #expect(StepTypeID.coldRetard.isColdRetard)
        #expect(StepTypeID.coldRetardBalls.isColdRetard)
        #expect(!StepTypeID.temper.isColdRetard)
        #expect(!StepTypeID.finalProof.isColdRetard)
    }
}
