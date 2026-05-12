@testable import Doug
import Foundation
import Testing

struct StarterStateMachineTests {
    // MARK: - Explicit Transitions

    @Test func activateFromDormant() {
        let result = StarterStateMachine.activate(currentState: .dormant)
        #expect(result?.newState == .activating)
    }

    @Test func activateFromActivatingIsNil() {
        #expect(StarterStateMachine.activate(currentState: .activating) == nil)
    }

    @Test func activateFromActiveIsNil() {
        #expect(StarterStateMachine.activate(currentState: .active) == nil)
    }

    @Test func activateFromRevivingIsNil() {
        #expect(StarterStateMachine.activate(currentState: .reviving) == nil)
    }

    @Test func refrigerateFromActivating() {
        let result = StarterStateMachine.refrigerate(currentState: .activating)
        #expect(result?.newState == .dormant)
    }

    @Test func refrigerateFromActive() {
        let result = StarterStateMachine.refrigerate(currentState: .active)
        #expect(result?.newState == .dormant)
    }

    @Test func refrigerateFromDormantIsNil() {
        #expect(StarterStateMachine.refrigerate(currentState: .dormant) == nil)
    }

    @Test func startRevivalFromDormant() {
        let result = StarterStateMachine.startRevival(currentState: .dormant)
        #expect(result?.newState == .reviving)
    }

    @Test func startRevivalFromActiveIsNil() {
        #expect(StarterStateMachine.startRevival(currentState: .active) == nil)
    }

    @Test func completeRevivalGoesToActivating() {
        let result = StarterStateMachine.completeRevival(currentState: .reviving)
        #expect(result?.newState == .activating)
    }

    @Test func cancelRevivalGoesToDormant() {
        let result = StarterStateMachine.cancelRevival(currentState: .reviving)
        #expect(result?.newState == .dormant)
    }

    // MARK: - Auto Transitions

    @Test func activatingWithGoodPeakTransitionsToActive() {
        let feed = FeedLogInput(
            timestamp: Date().addingTimeInterval(-300 * 60),
            ratioStarter: 1, ratioFlour: 5, ratioWater: 5,
            flourType: "white", kitchenTemperatureCelsius: 23,
            timeToPeakMinutes: 310,
            feedIntent: .activation
        )

        let result = StarterStateMachine.evaluateAutoTransition(
            currentState: .activating,
            stateChangedAt: Date().addingTimeInterval(-7200),
            lastActivationFeed: feed,
            activePeakAverage: 300
        )
        #expect(result?.newState == .active)
    }

    @Test func activatingWithSlowPeakStaysActivating() {
        let feed = FeedLogInput(
            timestamp: Date().addingTimeInterval(-500 * 60),
            ratioStarter: 1, ratioFlour: 5, ratioWater: 5,
            flourType: "white", kitchenTemperatureCelsius: 23,
            timeToPeakMinutes: 500,
            feedIntent: .activation
        )

        let result = StarterStateMachine.evaluateAutoTransition(
            currentState: .activating,
            stateChangedAt: Date().addingTimeInterval(-7200),
            lastActivationFeed: feed,
            activePeakAverage: 300
        )
        #expect(result == nil)
    }

    @Test func activatingWithNoPeakYetStaysActivating() {
        let feed = FeedLogInput(
            timestamp: Date().addingTimeInterval(-120 * 60),
            ratioStarter: 1, ratioFlour: 5, ratioWater: 5,
            flourType: "white", kitchenTemperatureCelsius: 23,
            timeToPeakMinutes: nil,
            feedIntent: .activation
        )

        let result = StarterStateMachine.evaluateAutoTransition(
            currentState: .activating,
            stateChangedAt: Date().addingTimeInterval(-7200),
            lastActivationFeed: feed,
            activePeakAverage: 300
        )
        #expect(result == nil)
    }

    @Test func activatingWithNoHistoryAndReasonablePeakTransitions() {
        let feed = FeedLogInput(
            timestamp: Date().addingTimeInterval(-360 * 60),
            ratioStarter: 1, ratioFlour: 5, ratioWater: 5,
            flourType: "white", kitchenTemperatureCelsius: 23,
            timeToPeakMinutes: 360,
            feedIntent: .activation
        )

        let result = StarterStateMachine.evaluateAutoTransition(
            currentState: .activating,
            stateChangedAt: Date().addingTimeInterval(-7200),
            lastActivationFeed: feed,
            activePeakAverage: nil
        )
        #expect(result?.newState == .active)
    }

    @Test func dormantHasNoAutoTransition() {
        let result = StarterStateMachine.evaluateAutoTransition(
            currentState: .dormant,
            stateChangedAt: Date(),
            lastActivationFeed: nil,
            activePeakAverage: nil
        )
        #expect(result == nil)
    }
}
