import Foundation

// MARK: - Feed Details (inline input from bake steps)

struct FeedDetails {
    let ratioStarter: Int
    let ratioFlour: Int
    let ratioWater: Int
    let flourType: String
    let kitchenTemperatureCelsius: Double
    let starterGrams: Double?
}

// MARK: - Side Effects

enum StarterSideEffect {
    case transitionLifecycle(StarterStateMachine.TransitionResult)
    case logFeed(FeedLogInput)
    case markPeakOnLatestFeed(FeedIntent)
    case updateStorageType(StarterStorageType)
}

// MARK: - Step Events

enum StepEvent {
    case started
    case completed
}

// MARK: - Bake Coordinator

enum BakeCoordinator {
    static func sideEffects(
        forStep stepTypeID: StepTypeID,
        event: StepEvent,
        starterState: StarterLifecycleState,
        feedDetails: FeedDetails?,
        kitchenTempCelsius: Double,
        now: Date = Date()
    ) -> [StarterSideEffect] {
        switch (stepTypeID, event) {
        case (.activateStarter, .completed):
            return activateStarterCompleted(
                starterState: starterState,
                feedDetails: feedDetails,
                kitchenTempCelsius: kitchenTempCelsius,
                now: now
            )

        case (.waitForPeak, .completed):
            return waitForPeakCompleted(starterState: starterState, now: now)

        case (.buildLevain, .started):
            return buildLevainStarted(
                feedDetails: feedDetails,
                kitchenTempCelsius: kitchenTempCelsius,
                now: now
            )

        case (.buildLevain, .completed):
            var effects: [StarterSideEffect] = [.markPeakOnLatestFeed(.levain)]
            if let transition = StarterStateMachine.markPeakConfirmed(currentState: starterState) {
                effects.insert(.transitionLifecycle(transition), at: 0)
            }
            return effects

        case (.refeedAndRefrigerate, .completed):
            return refeedAndRefrigerateCompleted(
                starterState: starterState,
                feedDetails: feedDetails,
                kitchenTempCelsius: kitchenTempCelsius,
                now: now
            )

        default:
            return []
        }
    }

    // MARK: - Step Handlers

    private static func activateStarterCompleted(
        starterState: StarterLifecycleState,
        feedDetails: FeedDetails?,
        kitchenTempCelsius: Double,
        now: Date
    ) -> [StarterSideEffect] {
        var effects: [StarterSideEffect] = []

        if let transition = StarterStateMachine.activate(currentState: starterState) {
            effects.append(.transitionLifecycle(transition))
        }

        effects.append(.updateStorageType(.counter))

        let details = feedDetails ?? FeedDetails(
            ratioStarter: 1, ratioFlour: 5, ratioWater: 5,
            flourType: "white", kitchenTemperatureCelsius: kitchenTempCelsius,
            starterGrams: nil
        )

        effects.append(.logFeed(FeedLogInput(
            timestamp: now,
            ratioStarter: details.ratioStarter,
            ratioFlour: details.ratioFlour,
            ratioWater: details.ratioWater,
            flourType: details.flourType,
            kitchenTemperatureCelsius: details.kitchenTemperatureCelsius,
            timeToPeakMinutes: nil,
            starterGrams: details.starterGrams,
            feedIntent: .activation
        )))

        return effects
    }

    private static func waitForPeakCompleted(
        starterState: StarterLifecycleState,
        now: Date
    ) -> [StarterSideEffect] {
        var effects: [StarterSideEffect] = []

        if let transition = StarterStateMachine.markPeakConfirmed(currentState: starterState) {
            effects.append(.transitionLifecycle(transition))
        }

        effects.append(.markPeakOnLatestFeed(.activation))

        return effects
    }

    private static func buildLevainStarted(
        feedDetails: FeedDetails?,
        kitchenTempCelsius: Double,
        now: Date
    ) -> [StarterSideEffect] {
        let details = feedDetails ?? FeedDetails(
            ratioStarter: 1, ratioFlour: 5, ratioWater: 5,
            flourType: "white", kitchenTemperatureCelsius: kitchenTempCelsius,
            starterGrams: nil
        )

        return [.logFeed(FeedLogInput(
            timestamp: now,
            ratioStarter: details.ratioStarter,
            ratioFlour: details.ratioFlour,
            ratioWater: details.ratioWater,
            flourType: details.flourType,
            kitchenTemperatureCelsius: details.kitchenTemperatureCelsius,
            timeToPeakMinutes: nil,
            starterGrams: details.starterGrams,
            feedIntent: .levain
        ))]
    }

    private static func refeedAndRefrigerateCompleted(
        starterState: StarterLifecycleState,
        feedDetails: FeedDetails?,
        kitchenTempCelsius: Double,
        now: Date
    ) -> [StarterSideEffect] {
        var effects: [StarterSideEffect] = []

        if let transition = StarterStateMachine.refrigerate(currentState: starterState) {
            effects.append(.transitionLifecycle(transition))
        }

        effects.append(.updateStorageType(.fridge))

        let details = feedDetails ?? FeedDetails(
            ratioStarter: 1, ratioFlour: 1, ratioWater: 1,
            flourType: "white", kitchenTemperatureCelsius: kitchenTempCelsius,
            starterGrams: nil
        )

        effects.append(.logFeed(FeedLogInput(
            timestamp: now,
            ratioStarter: details.ratioStarter,
            ratioFlour: details.ratioFlour,
            ratioWater: details.ratioWater,
            flourType: details.flourType,
            kitchenTemperatureCelsius: details.kitchenTemperatureCelsius,
            timeToPeakMinutes: nil,
            starterGrams: details.starterGrams,
            feedIntent: .postBake
        )))

        return effects
    }
}
