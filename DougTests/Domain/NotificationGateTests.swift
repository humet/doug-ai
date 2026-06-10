#if canImport(DougDomain)
    @testable import DougDomain
#else
    @testable import Doug
#endif
import Foundation
import Testing

struct NotificationGateTests {
    private func info(_ id: StepTypeID, pending: Bool = true) -> NotificationGate.StepInfo {
        NotificationGate.StepInfo(stepTypeID: id.rawValue, isPending: pending)
    }

    @Test func bakerJudgedStepsAreGates() {
        #expect(NotificationGate.isGate(stepTypeID: StepTypeID.waitForPeak.rawValue))
        #expect(NotificationGate.isGate(stepTypeID: StepTypeID.waitForLevainPeak.rawValue))
        #expect(NotificationGate.isGate(stepTypeID: StepTypeID.bulkFerment.rawValue))
    }

    @Test func clockDrivenStepsAreNotGates() {
        #expect(!NotificationGate.isGate(stepTypeID: StepTypeID.buildLevain.rawValue))
        #expect(!NotificationGate.isGate(stepTypeID: StepTypeID.autolyse.rawValue))
        #expect(!NotificationGate.isGate(stepTypeID: StepTypeID.coldRetard.rawValue))
        #expect(!NotificationGate.isGate(stepTypeID: StepTypeID.preheat.rawValue))
        #expect(!NotificationGate.isGate(stepTypeID: StepTypeID.bake.rawValue))
    }

    @Test func firstPendingGateIsTheLevainWait() {
        let steps = [
            info(.buildLevain, pending: false),
            info(.waitForLevainPeak),
            info(.autolyse),
            info(.mix),
            info(.bulkFerment),
        ]
        #expect(NotificationGate.firstPendingGateIndex(in: steps) == 1)
    }

    @Test func completedGatesAreSkippedOverToTheNextPendingGate() {
        let steps = [
            info(.buildLevain, pending: false),
            info(.waitForLevainPeak, pending: false),
            info(.autolyse, pending: false),
            info(.mix),
            info(.bulkFerment),
            info(.shape),
        ]
        #expect(NotificationGate.firstPendingGateIndex(in: steps) == 4)
    }

    @Test func noPendingGateMeansNoCutoff() {
        let steps = [
            info(.waitForLevainPeak, pending: false),
            info(.bulkFerment, pending: false),
            info(.shape),
            info(.coldRetard),
            info(.bake),
        ]
        #expect(NotificationGate.firstPendingGateIndex(in: steps) == nil)
    }

    @Test func activeGateStillGates() {
        // The reported bug: while "waiting for peak" is the active step,
        // notifications for later steps must not exist yet.
        let steps = [
            info(.buildLevain, pending: false),
            info(.waitForLevainPeak, pending: true),
            info(.mix),
        ]
        #expect(NotificationGate.firstPendingGateIndex(in: steps) == 1)
    }
}
