#if canImport(DougDomain)
    @testable import DougDomain
#else
    @testable import Doug
#endif
import Foundation
import Testing

struct NotificationPolicyTests {
    @Test func suppressesCompletionWhenNextStepIsHandsOn() {
        // Autolyse → mix: the mix reminder fires 5 min before the autolyse
        // timer completes, so the completion notification is redundant.
        #expect(!NotificationPolicy.shouldScheduleFlexibleCompletion(
            nextTopLevelStepTypeID: StepTypeID.mix.rawValue
        ))
        #expect(!NotificationPolicy.shouldScheduleFlexibleCompletion(
            nextTopLevelStepTypeID: StepTypeID.shape.rawValue
        ))
    }

    @Test func suppressesCompletionWhenNextStepIsPreheat() {
        // Cold retard / final proof → preheat.
        #expect(!NotificationPolicy.shouldScheduleFlexibleCompletion(
            nextTopLevelStepTypeID: StepTypeID.preheat.rawValue
        ))
    }

    @Test func schedulesCompletionWhenNextStepGetsNoStartReminder() {
        #expect(NotificationPolicy.shouldScheduleFlexibleCompletion(
            nextTopLevelStepTypeID: StepTypeID.bulkFerment.rawValue
        ))
        #expect(NotificationPolicy.shouldScheduleFlexibleCompletion(
            nextTopLevelStepTypeID: StepTypeID.coldRetard.rawValue
        ))
    }

    @Test func schedulesCompletionForLastOrUnknownStep() {
        #expect(NotificationPolicy.shouldScheduleFlexibleCompletion(nextTopLevelStepTypeID: nil))
        #expect(NotificationPolicy.shouldScheduleFlexibleCompletion(nextTopLevelStepTypeID: "not-a-step"))
    }

    @Test func bulkGateCheckCopyAsksForAJudgement() {
        let copy = StepTypeRegistry.gateCheckNotificationText(for: .bulkFerment)
        #expect(copy.localizedCaseInsensitiveContains("check your dough"))
        #expect(copy.contains("50–75%"))
        #expect(!copy.localizedCaseInsensitiveContains("underway"))
    }

    @Test func levainGateCheckFallsBackToStepCopy() {
        let copy = StepTypeRegistry.gateCheckNotificationText(for: .waitForLevainPeak)
        #expect(copy == StepTypeRegistry.type(for: .waitForLevainPeak).notificationText)
    }
}
