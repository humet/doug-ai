@testable import Doug
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
}
