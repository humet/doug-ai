#if canImport(DougDomain)
    @testable import DougDomain
#else
    @testable import Doug
#endif
import Testing

struct FeedInstructionsTests {
    @Test func revivalFirstWithHoochIncludesPourOff() {
        let input = FeedInstructionInput(
            retainGrams: 20,
            addFlourGrams: 40,
            addWaterGrams: 40,
            flourType: "white",
            kitchenTempC: 22,
            expectedPeakMinutes: 480,
            kind: .revivalFirst,
            hadHooch: true,
            neglect: .moderate
        )
        let instr = FeedInstructions.instruction(for: input)
        #expect(!instr.steps.isEmpty)
        #expect(instr.steps.contains { $0.lowercased().contains("pour off") })
        #expect(instr.steps.contains { $0.contains("20 g") })
        #expect(instr.steps.contains { $0.contains("40 g") })
    }

    @Test func revivalFirstWithoutHoochSkipsPourOff() {
        let input = FeedInstructionInput(
            retainGrams: 20,
            addFlourGrams: 40,
            addWaterGrams: 40,
            flourType: "white",
            kitchenTempC: 22,
            expectedPeakMinutes: 360,
            kind: .revivalFirst,
            hadHooch: false,
            neglect: .mild
        )
        let instr = FeedInstructions.instruction(for: input)
        #expect(!instr.steps.contains { $0.lowercased().contains("pour off") })
    }

    @Test func severeNeglectWatchForDiffersFromMild() {
        let mildInput = FeedInstructionInput(
            retainGrams: 20, addFlourGrams: 40, addWaterGrams: 40,
            flourType: "white", kitchenTempC: 22, expectedPeakMinutes: 360,
            kind: .revivalFirst, hadHooch: false, neglect: .mild
        )
        let severeInput = FeedInstructionInput(
            retainGrams: 20, addFlourGrams: 40, addWaterGrams: 40,
            flourType: "white", kitchenTempC: 22, expectedPeakMinutes: 600,
            kind: .revivalFirst, hadHooch: true, neglect: .severe
        )
        #expect(FeedInstructions.instruction(for: mildInput).watchFor
            != FeedInstructions.instruction(for: severeInput).watchFor)
    }

    @Test func maintenanceIncludesFlourTypeAndGrams() {
        let input = FeedInstructionInput(
            retainGrams: 10,
            addFlourGrams: 50,
            addWaterGrams: 50,
            flourType: "rye",
            kitchenTempC: 22,
            expectedPeakMinutes: 300,
            kind: .maintenance,
            hadHooch: false,
            neglect: nil
        )
        let instr = FeedInstructions.instruction(for: input)
        #expect(!instr.steps.isEmpty)
        #expect(instr.steps.contains { $0.contains("10 g") })
        #expect(instr.steps.contains { $0.contains("50 g") })
    }

    @Test func levainBuildIncludesGramsAndPeakGuidance() {
        let input = FeedInstructionInput(
            retainGrams: 11,
            addFlourGrams: 57,
            addWaterGrams: 57,
            flourType: "white",
            kitchenTempC: 24,
            expectedPeakMinutes: 300,
            kind: .levain,
            hadHooch: false,
            neglect: nil
        )
        let instr = FeedInstructions.instruction(for: input)
        #expect(instr.title == "Build your levain")
        #expect(instr.steps.contains { $0.contains("11 g") })
        #expect(instr.steps.contains { $0.contains("57 g") })
        #expect(instr.peakGuidance.contains("fridge"))
    }

    @Test func allKindsYieldNonEmpty() {
        let kinds: [FeedStepKind] = [.revivalFirst, .revivalMiddle, .revivalFinal, .maintenance, .levain]
        for kind in kinds {
            let input = FeedInstructionInput(
                retainGrams: 20, addFlourGrams: 40, addWaterGrams: 40,
                flourType: "white", kitchenTempC: 22, expectedPeakMinutes: 300,
                kind: kind, hadHooch: false, neglect: .mild
            )
            let instr = FeedInstructions.instruction(for: input)
            #expect(!instr.title.isEmpty)
            #expect(!instr.steps.isEmpty)
            #expect(!instr.watchFor.isEmpty)
            #expect(!instr.expectedWait.isEmpty)
        }
    }

    // MARK: - New Starter

    private static func newStarterInput(
        kind: FeedStepKind,
        retain: Double = 50,
        flour: Double = 50,
        water: Double = 50,
        day: Int? = nil,
        origin: StarterOrigin = .fromScratch
    ) -> FeedInstructionInput {
        FeedInstructionInput(
            retainGrams: retain,
            addFlourGrams: flour,
            addWaterGrams: water,
            flourType: "whole wheat",
            kitchenTempC: 22,
            expectedPeakMinutes: 360,
            kind: kind,
            hadHooch: false,
            neglect: nil,
            origin: origin,
            dayNumber: day
        )
    }

    @Test func everyNewStarterKindProducesUsableCopy() {
        let kinds: [FeedStepKind] = [
            .initialMix, .rehydrate, .activateGift, .dailyFeed, .twiceDailyFeed, .readinessTest,
        ]
        for kind in kinds {
            let instruction = FeedInstructions.instruction(for: Self.newStarterInput(kind: kind))
            #expect(!instruction.title.isEmpty, "\(kind) had no title")
            #expect(!instruction.steps.isEmpty, "\(kind) had no steps")
            #expect(!instruction.watchFor.isEmpty, "\(kind) had nothing to watch for")
            #expect(!instruction.peakGuidance.isEmpty, "\(kind) had no peak guidance")
        }
    }

    @Test func theFirstScratchMixNeverMentionsRetainingStarter() {
        // There is no starter yet — telling someone to keep 0 g of it is nonsense.
        let instruction = FeedInstructions.instruction(
            for: Self.newStarterInput(kind: .initialMix, retain: 0)
        )
        let body = instruction.steps.joined(separator: " ").lowercased()
        #expect(!body.contains("discard"))
        #expect(!body.contains("existing starter"))
        #expect(body.contains("flour"))
        #expect(body.contains("water"))
    }

    @Test func aDriedCultureFirstMixThickensTheExistingSlurry() {
        let instruction = FeedInstructions.instruction(
            for: Self.newStarterInput(kind: .initialMix, retain: 30, flour: 30, water: 0, origin: .driedCulture)
        )
        #expect(instruction.steps.joined(separator: " ").lowercased().contains("slurry"))
    }

    @Test func rehydrationWarnsAgainstHotWater() {
        // Hot water kills the culture — the one way to fail this step outright.
        let instruction = FeedInstructions.instruction(
            for: Self.newStarterInput(kind: .rehydrate, retain: 5, flour: 0, water: 25, origin: .driedCulture)
        )
        let body = instruction.steps.joined(separator: " ").lowercased()
        #expect(body.contains("30"))
        #expect(body.contains("never hot"))
    }

    @Test func theDayThreeFeedWarnsAboutTheFalseRise() {
        let instruction = FeedInstructions.instruction(
            for: Self.newStarterInput(kind: .dailyFeed, day: 3)
        )
        let text = instruction.watchFor.lowercased()
        #expect(text.contains("cheesy") || text.contains("funky"))
        #expect(text.contains("bacteria"))
    }

    @Test func earlyDaysSetExpectationsThatNothingHappens() {
        let instruction = FeedInstructions.instruction(
            for: Self.newStarterInput(kind: .dailyFeed, day: 2)
        )
        #expect(instruction.watchFor.lowercased().contains("nothing"))
    }

    @Test func dailyFeedTitlesCarryTheDayNumber() {
        let instruction = FeedInstructions.instruction(
            for: Self.newStarterInput(kind: .dailyFeed, day: 4)
        )
        #expect(instruction.title.contains("4"))
    }

    @Test func theConfirmingFeedExplainsTheTest() {
        let instruction = FeedInstructions.instruction(
            for: Self.newStarterInput(kind: .readinessTest, retain: 25)
        )
        #expect(instruction.peakGuidance.lowercased().contains("twice in a row"))
    }

    @Test func stepKindsMapOntoInstructionTemplates() {
        #expect(StarterStepKind.initialMix.feedStepKind == .initialMix)
        #expect(StarterStepKind.rehydrate.feedStepKind == .rehydrate)
        #expect(StarterStepKind.dailyFeed.feedStepKind == .dailyFeed)
        #expect(StarterStepKind.readinessTest.feedStepKind == .readinessTest)
        // A revival feed keeps using the existing revival copy.
        #expect(StarterStepKind.revivalFeed.feedStepKind == .revivalMiddle)
    }
}
