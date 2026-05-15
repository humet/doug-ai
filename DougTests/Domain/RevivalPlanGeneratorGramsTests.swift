#if canImport(DougDomain)
@testable import DougDomain
#else
@testable import Doug
#endif
import Foundation
import Testing

struct RevivalPlanGeneratorGramsTests {
    private static let availability = AvailabilityInput(
        startHour: 0, startMinute: 0, endHour: 23, endMinute: 59
    )

    @Test func mildYieldsThreeFeedsWithCorrectGrams() {
        let plans = RevivalPlanGenerator.generate(
            startTime: Date(),
            initialStarterGrams: 20,
            neglect: .mild,
            availability: Self.availability,
            windows: []
        )
        #expect(plans.count == 3)
        for plan in plans {
            #expect(plan.retainStarterGrams == 20)
            #expect(plan.addFlourGrams == 40)
            #expect(plan.addWaterGrams == 40)
        }
    }

    @Test func severeYieldsFourFeeds() {
        let plans = RevivalPlanGenerator.generate(
            startTime: Date(),
            initialStarterGrams: 20,
            neglect: .severe,
            availability: Self.availability,
            windows: []
        )
        #expect(plans.count == 4)
        #expect(plans[0].expectedPeakMinutes == 600)
    }

    @Test func moderateHasLongerFirstWait() {
        let plans = RevivalPlanGenerator.generate(
            startTime: Date(),
            initialStarterGrams: 20,
            neglect: .moderate,
            availability: Self.availability,
            windows: []
        )
        #expect(plans[0].expectedPeakMinutes == 480)
    }

    @Test func toleranceBandsAreDerivedFromExpected() {
        let plans = RevivalPlanGenerator.generate(
            startTime: Date(),
            initialStarterGrams: 20,
            neglect: .mild,
            availability: Self.availability,
            windows: []
        )
        let first = plans[0]
        #expect(first.minPeakMinutes == first.expectedPeakMinutes * 0.75)
        #expect(first.maxPeakMinutes == first.expectedPeakMinutes * 1.5)
    }

    @Test func differentStarterAmountScalesAll() {
        let plans = RevivalPlanGenerator.generate(
            startTime: Date(),
            initialStarterGrams: 50,
            neglect: .mild,
            availability: Self.availability,
            windows: []
        )
        for plan in plans {
            #expect(plan.retainStarterGrams == 50)
            #expect(plan.addFlourGrams == 100)
            #expect(plan.addWaterGrams == 100)
        }
    }

    @Test func stepKindMapping() {
        #expect(RevivalPlanGenerator.stepKind(index: 0, totalSteps: 3) == .revivalFirst)
        #expect(RevivalPlanGenerator.stepKind(index: 1, totalSteps: 3) == .revivalMiddle)
        #expect(RevivalPlanGenerator.stepKind(index: 2, totalSteps: 3) == .revivalFinal)
        #expect(RevivalPlanGenerator.stepKind(index: 3, totalSteps: 4) == .revivalFinal)
    }
}

extension FeedStepKind: @retroactive Equatable {
    public static func == (lhs: FeedStepKind, rhs: FeedStepKind) -> Bool {
        switch (lhs, rhs) {
        case (.revivalFirst, .revivalFirst),
             (.revivalMiddle, .revivalMiddle),
             (.revivalFinal, .revivalFinal),
             (.maintenance, .maintenance):
            true
        default:
            false
        }
    }
}
