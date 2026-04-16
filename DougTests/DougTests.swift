import Testing
@testable import Doug

struct RecipeTests {
    @Test func allRecipesExist() {
        #expect(RecipeBook.all.count == 4)
    }

    @Test func recipeIDsAreUnique() {
        let ids = RecipeBook.all.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test func lookupByID() {
        for recipe in RecipeBook.all {
            let found = RecipeBook.recipe(for: recipe.id)
            #expect(found.name == recipe.name)
        }
    }

    @Test func countryLoafHasCorrectMethod() {
        let recipe = RecipeBook.countryLoaf
        #expect(recipe.hydrationPercent == 70)
        #expect(recipe.degreeHourTarget == 80)

        let stepTypes = recipe.method.map(\.stepTypeID)
        #expect(stepTypes.first == .buildLevain)
        #expect(stepTypes.last == .bakeUncovered)
        #expect(stepTypes.contains(.bulkFerment))
    }

    @Test func oliveRosemaryHasInclusions() {
        let recipe = RecipeBook.oliveRosemary
        let bulkStep = recipe.method.first(where: { $0.stepTypeID == .bulkFerment })
        #expect(bulkStep?.inclusionAtFold == 2)
        #expect(recipe.ingredients.extras.count == 2)
    }
}

struct StepTypeTests {
    @Test func allStepTypesRegistered() {
        for id in StepTypeID.allCases {
            let stepType = StepTypeRegistry.type(for: id)
            #expect(!stepType.label.isEmpty)
        }
    }

    @Test func classificationsAreCorrect() {
        #expect(StepTypeRegistry.type(for: .mix).classification == .handsOn)
        #expect(StepTypeRegistry.type(for: .stretchAndFold).classification == .handsOn)
        #expect(StepTypeRegistry.type(for: .shape).classification == .handsOn)
        #expect(StepTypeRegistry.type(for: .autolyse).classification == .passiveFlexible)
        #expect(StepTypeRegistry.type(for: .coldRetard).classification == .passiveFlexible)
        #expect(StepTypeRegistry.type(for: .bulkFerment).classification == .passiveFixed)
        #expect(StepTypeRegistry.type(for: .preheat).classification == .passiveFixed)
    }

    @Test func temperatureAdjustedSteps() {
        #expect(StepTypeRegistry.type(for: .buildLevain).isTemperatureAdjusted)
        #expect(StepTypeRegistry.type(for: .bulkFerment).isTemperatureAdjusted)
        #expect(!StepTypeRegistry.type(for: .mix).isTemperatureAdjusted)
        #expect(!StepTypeRegistry.type(for: .coldRetard).isTemperatureAdjusted)
    }

    @Test func tempReadingRequirements() {
        #expect(StepTypeRegistry.type(for: .mix).requiresTempReading)
        #expect(StepTypeRegistry.type(for: .stretchAndFold).requiresTempReading)
        #expect(!StepTypeRegistry.type(for: .shape).requiresTempReading)
        #expect(!StepTypeRegistry.type(for: .preheat).requiresTempReading)
    }
}

struct MethodStepTests {
    @Test func effectiveDurationUsesOverride() {
        let step = MethodStep(stepTypeID: .autolyse, durationOverrideMinutes: 30)
        #expect(step.effectiveDuration == 30)
    }

    @Test func effectiveDurationFallsBackToDefault() {
        let step = MethodStep(stepTypeID: .mix)
        #expect(step.effectiveDuration == 5)
    }

    @Test func effectiveFlexRangeUsesOverride() {
        let step = MethodStep(stepTypeID: .coldRetard, flexRangeOverride: 600...1080)
        #expect(step.effectiveFlexRange == 600...1080)
    }
}
