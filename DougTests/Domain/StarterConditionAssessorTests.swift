@testable import Doug
import Testing

struct StarterConditionAssessorTests {
    @Test func moldAlwaysDiscards() {
        let input = StarterConditionInput(
            daysSinceLastFed: 2,
            hasHooch: false,
            smellsStronglyAcetone: false,
            hasBubbles: true,
            hasPinkOrangeOrMold: true
        )
        #expect(StarterConditionAssessor.assess(input).isDiscard)
    }

    @Test func moldOverridesEverything() {
        let input = StarterConditionInput(
            daysSinceLastFed: 30,
            hasHooch: true,
            smellsStronglyAcetone: true,
            hasBubbles: false,
            hasPinkOrangeOrMold: true
        )
        #expect(StarterConditionAssessor.assess(input).isDiscard)
    }

    @Test func freshStarterIsMild() {
        let input = StarterConditionInput(
            daysSinceLastFed: 2,
            hasHooch: false,
            smellsStronglyAcetone: false,
            hasBubbles: true,
            hasPinkOrangeOrMold: false
        )
        #expect(StarterConditionAssessor.assess(input) == .safeToRevive(.mild))
    }

    @Test func hoochAlonePromotesToModerate() {
        let input = StarterConditionInput(
            daysSinceLastFed: 3,
            hasHooch: true,
            smellsStronglyAcetone: false,
            hasBubbles: false,
            hasPinkOrangeOrMold: false
        )
        #expect(StarterConditionAssessor.assess(input) == .safeToRevive(.moderate))
    }

    @Test func oneWeekIsModerate() {
        let input = StarterConditionInput(
            daysSinceLastFed: 10,
            hasHooch: false,
            smellsStronglyAcetone: false,
            hasBubbles: false,
            hasPinkOrangeOrMold: false
        )
        #expect(StarterConditionAssessor.assess(input) == .safeToRevive(.moderate))
    }

    @Test func threeWeeksIsSevere() {
        let input = StarterConditionInput(
            daysSinceLastFed: 22,
            hasHooch: true,
            smellsStronglyAcetone: false,
            hasBubbles: false,
            hasPinkOrangeOrMold: false
        )
        #expect(StarterConditionAssessor.assess(input) == .safeToRevive(.severe))
    }

    @Test func hoochPlusAcetoneIsSevere() {
        let input = StarterConditionInput(
            daysSinceLastFed: 5,
            hasHooch: true,
            smellsStronglyAcetone: true,
            hasBubbles: false,
            hasPinkOrangeOrMold: false
        )
        #expect(StarterConditionAssessor.assess(input) == .safeToRevive(.severe))
    }

    @Test func unknownDaysWithNoSignalsIsMild() {
        let input = StarterConditionInput(
            daysSinceLastFed: nil,
            hasHooch: false,
            smellsStronglyAcetone: false,
            hasBubbles: false,
            hasPinkOrangeOrMold: false
        )
        #expect(StarterConditionAssessor.assess(input) == .safeToRevive(.mild))
    }
}

private extension StarterSafetyVerdict {
    var isDiscard: Bool {
        if case .discardAndRestart = self { return true }
        return false
    }
}
