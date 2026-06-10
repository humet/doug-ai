#if canImport(DougDomain)
    @testable import DougDomain
#else
    @testable import Doug
#endif
import Foundation
import Testing

struct StarterScheduleSyncTests {
    let now = Date(timeIntervalSince1970: 1_750_000_000)

    /// A dormant-starter preamble: resting filler, activate, wait for peak,
    /// then the first recipe steps.
    func dormantPreamble(
        fillerStatus: StepStatus = .active,
        activateStatus: StepStatus = .upcoming,
        waitStatus: StepStatus = .upcoming
    ) -> [ScheduleStepSnapshot] {
        [
            ScheduleStepSnapshot(
                index: 0, stepTypeID: .fridgeRest, status: fillerStatus,
                startTime: now, endTime: now.addingTimeInterval(2 * 3600)
            ),
            ScheduleStepSnapshot(
                index: 1, stepTypeID: .activateStarter, status: activateStatus,
                startTime: now.addingTimeInterval(2 * 3600),
                endTime: now.addingTimeInterval(2 * 3600 + 600)
            ),
            ScheduleStepSnapshot(
                index: 2, stepTypeID: .waitForPeak, status: waitStatus,
                startTime: now.addingTimeInterval(2 * 3600 + 600),
                endTime: now.addingTimeInterval(8 * 3600)
            ),
            ScheduleStepSnapshot(
                index: 3, stepTypeID: .buildLevain, status: .upcoming,
                startTime: now.addingTimeInterval(8 * 3600),
                endTime: now.addingTimeInterval(8 * 3600 + 900)
            ),
        ]
    }

    // MARK: - Activated

    @Test func activatedCompletesFillerAndStartsActivateStep() {
        let at = now.addingTimeInterval(600)
        let effects = StarterScheduleSync.effects(
            for: .activated(at: at),
            steps: dormantPreamble(),
            expectedPeakMinutes: 360,
            now: at
        )

        #expect(effects == [
            .completeStep(index: 0, at: at),
            .startStep(index: 1, at: at),
        ])
    }

    @Test func activatedIsNoOpWhenActivateStepAlreadyDone() {
        let at = now.addingTimeInterval(600)
        let effects = StarterScheduleSync.effects(
            for: .activated(at: at),
            steps: dormantPreamble(fillerStatus: .done, activateStatus: .done),
            expectedPeakMinutes: 360,
            now: at
        )
        #expect(effects.isEmpty)
    }

    @Test func activatedIsNoOpWithoutPreamble() {
        let steps = [
            ScheduleStepSnapshot(
                index: 0, stepTypeID: .buildLevain, status: .upcoming,
                startTime: now, endTime: now.addingTimeInterval(900)
            ),
        ]
        let effects = StarterScheduleSync.effects(
            for: .activated(at: now),
            steps: steps,
            expectedPeakMinutes: 360,
            now: now
        )
        #expect(effects.isEmpty)
    }

    // MARK: - Activation feed logged

    @Test func feedLoggedCompletesPreambleAndRetimesWait() {
        let at = now.addingTimeInterval(600)
        let effects = StarterScheduleSync.effects(
            for: .activationFeedLogged(at: at),
            steps: dormantPreamble(),
            expectedPeakMinutes: 360,
            now: at
        )

        #expect(effects == [
            .completeStep(index: 0, at: at),
            .completeStep(index: 1, at: at),
            .retimeStepEnd(index: 2, newEnd: at.addingTimeInterval(360 * 60)),
        ])
    }

    @Test func secondFeedOnlyRetimesWait() {
        let at = now.addingTimeInterval(3 * 3600)
        let effects = StarterScheduleSync.effects(
            for: .activationFeedLogged(at: at),
            steps: dormantPreamble(fillerStatus: .done, activateStatus: .done, waitStatus: .active),
            expectedPeakMinutes: 360,
            now: at
        )
        #expect(effects == [.retimeStepEnd(index: 2, newEnd: at.addingTimeInterval(360 * 60))])
    }

    @Test func feedRetimeNeverEndsBeforeNow() {
        // Feed logged with a backdated timestamp far enough in the past that
        // feed + expected peak is already behind us — the wait still ends now,
        // not in the past.
        let feedAt = now.addingTimeInterval(-10 * 3600)
        let effects = StarterScheduleSync.effects(
            for: .activationFeedLogged(at: feedAt),
            steps: dormantPreamble(fillerStatus: .done, activateStatus: .done, waitStatus: .active),
            expectedPeakMinutes: 360,
            now: now
        )
        #expect(effects == [.retimeStepEnd(index: 2, newEnd: now)])
    }

    // MARK: - Levain feed logged

    @Test func levainFeedCompletesOpenPreambleAndBuildStep() {
        let at = now.addingTimeInterval(7 * 3600)
        let effects = StarterScheduleSync.effects(
            for: .levainFeedLogged(at: at),
            steps: dormantPreamble(fillerStatus: .done, activateStatus: .done, waitStatus: .active),
            expectedPeakMinutes: 360,
            now: at
        )
        #expect(effects == [
            .completeStep(index: 2, at: at),
            .completeStep(index: 3, at: at),
        ])
    }

    @Test func levainFeedIsNoOpWithoutOpenBuildStep() {
        let steps = [
            ScheduleStepSnapshot(
                index: 0, stepTypeID: .buildLevain, status: .done,
                startTime: now, endTime: now.addingTimeInterval(900)
            ),
        ]
        let effects = StarterScheduleSync.effects(
            for: .levainFeedLogged(at: now),
            steps: steps,
            expectedPeakMinutes: 360,
            now: now
        )
        #expect(effects.isEmpty)
    }

    // MARK: - Peak marked

    @Test func activationPeakCompletesPredecessorsThenWait() {
        let at = now.addingTimeInterval(7 * 3600)
        let effects = StarterScheduleSync.effects(
            for: .peakMarked(at: at, intent: .activation),
            steps: dormantPreamble(),
            expectedPeakMinutes: 360,
            now: at
        )

        #expect(effects == [
            .completeStep(index: 0, at: at),
            .completeStep(index: 1, at: at),
            .completeStep(index: 2, at: at),
        ])
    }

    @Test func backdatedPeakCompletesWaitAtBackdate() {
        let backdated = now.addingTimeInterval(5 * 3600)
        let later = now.addingTimeInterval(9 * 3600)
        let effects = StarterScheduleSync.effects(
            for: .peakMarked(at: backdated, intent: .activation),
            steps: dormantPreamble(fillerStatus: .done, activateStatus: .done, waitStatus: .active),
            expectedPeakMinutes: 360,
            now: later
        )
        #expect(effects == [.completeStep(index: 2, at: backdated)])
    }

    @Test func activationPeakIsNoOpWithoutOpenWaitStep() {
        let effects = StarterScheduleSync.effects(
            for: .peakMarked(at: now, intent: .activation),
            steps: dormantPreamble(fillerStatus: .done, activateStatus: .done, waitStatus: .done),
            expectedPeakMinutes: 360,
            now: now
        )
        #expect(effects.isEmpty)
    }

    @Test func levainPeakTargetsWaitForLevainPeak() {
        let steps = [
            ScheduleStepSnapshot(
                index: 0, stepTypeID: .buildLevain, status: .done,
                startTime: now, endTime: now.addingTimeInterval(900)
            ),
            ScheduleStepSnapshot(
                index: 1, stepTypeID: .waitForLevainPeak, status: .active,
                startTime: now.addingTimeInterval(900),
                endTime: now.addingTimeInterval(6 * 3600)
            ),
        ]
        let at = now.addingTimeInterval(5 * 3600)
        let effects = StarterScheduleSync.effects(
            for: .peakMarked(at: at, intent: .levain),
            steps: steps,
            expectedPeakMinutes: 360,
            now: at
        )
        #expect(effects == [.completeStep(index: 1, at: at)])
    }

    @Test func maintenancePeakHasNoEffects() {
        let effects = StarterScheduleSync.effects(
            for: .peakMarked(at: now, intent: .maintenance),
            steps: dormantPreamble(),
            expectedPeakMinutes: 360,
            now: now
        )
        #expect(effects.isEmpty)
    }

    @Test func emptyScheduleHasNoEffects() {
        let effects = StarterScheduleSync.effects(
            for: .activationFeedLogged(at: now),
            steps: [],
            expectedPeakMinutes: 360,
            now: now
        )
        #expect(effects.isEmpty)
    }

    // MARK: - Expected peak fallback chain

    @Test func expectedPeakPrefersObservedBucketAverage() {
        let logs = (0 ..< 3).map { i in
            FeedLogInput(
                timestamp: now.addingTimeInterval(Double(i) * 86400),
                ratioStarter: 1, ratioFlour: 5, ratioWater: 5,
                flourType: "white", kitchenTemperatureCelsius: 23,
                timeToPeakMinutes: 300, feedIntent: .activation
            )
        }
        let profile = StarterPeakProfile(feedLogs: logs, intentFilter: .activation)
        let minutes = StarterScheduleSync.expectedPeakMinutes(
            peakProfile: profile,
            activePeakAverageMinutes: 500,
            kitchenTempCelsius: 23
        )
        #expect(minutes == 300)
    }

    @Test func expectedPeakFallsBackToProfileAverageThenTemperature() {
        let fromProfileAvg = StarterScheduleSync.expectedPeakMinutes(
            peakProfile: nil,
            activePeakAverageMinutes: 500,
            kitchenTempCelsius: 23
        )
        #expect(fromProfileAvg == 500)

        let fromTemperature = StarterScheduleSync.expectedPeakMinutes(
            peakProfile: nil,
            activePeakAverageMinutes: nil,
            kitchenTempCelsius: 23
        )
        #expect(fromTemperature == TemperatureCalculator.levainBuildMinutes(kitchenTemp: 23))
    }
}
