#if canImport(DougDomain)
@testable import DougDomain
#else
@testable import Doug
#endif
import Foundation
import Testing

struct BakeCoordinatorTests {
    // MARK: - Activate Starter

    @Test func activateStarterCompletedFromDormant() {
        let effects = BakeCoordinator.sideEffects(
            forStep: .activateStarter,
            event: .completed,
            starterState: .dormant,
            feedDetails: nil,
            kitchenTempCelsius: 22
        )

        let hasTransition = effects.contains {
            if case let .transitionLifecycle(result) = $0 { return result.newState == .activating }
            return false
        }
        let hasStorageUpdate = effects.contains {
            if case let .updateStorageType(type) = $0 { return type == .counter }
            return false
        }
        let hasFeedLog = effects.contains {
            if case let .logFeed(input) = $0 { return input.feedIntent == .activation }
            return false
        }

        #expect(hasTransition)
        #expect(hasStorageUpdate)
        #expect(hasFeedLog)
    }

    @Test func activateStarterUsesCustomFeedDetails() {
        let details = FeedDetails(
            ratioStarter: 1, ratioFlour: 3, ratioWater: 3,
            flourType: "rye", kitchenTemperatureCelsius: 25,
            starterGrams: 20
        )

        let effects = BakeCoordinator.sideEffects(
            forStep: .activateStarter,
            event: .completed,
            starterState: .dormant,
            feedDetails: details,
            kitchenTempCelsius: 22
        )

        let feedLog = effects.compactMap { effect -> FeedLogInput? in
            if case let .logFeed(input) = effect { return input }
            return nil
        }.first

        #expect(feedLog?.ratioFlour == 3)
        #expect(feedLog?.flourType == "rye")
        #expect(feedLog?.kitchenTemperatureCelsius == 25)
    }

    // MARK: - Wait for Peak

    @Test func waitForPeakCompletedTransitionsToActive() {
        let effects = BakeCoordinator.sideEffects(
            forStep: .waitForPeak,
            event: .completed,
            starterState: .activating,
            feedDetails: nil,
            kitchenTempCelsius: 22
        )

        let hasTransition = effects.contains {
            if case let .transitionLifecycle(result) = $0 { return result.newState == .active }
            return false
        }
        let hasPeakMark = effects.contains {
            if case let .markPeakOnLatestFeed(intent) = $0 { return intent == .activation }
            return false
        }

        #expect(hasTransition)
        #expect(hasPeakMark)
    }

    // MARK: - Build Levain

    @Test func buildLevainStartedLogsFeed() {
        let effects = BakeCoordinator.sideEffects(
            forStep: .buildLevain,
            event: .started,
            starterState: .active,
            feedDetails: nil,
            kitchenTempCelsius: 24
        )

        let hasFeed = effects.contains {
            if case let .logFeed(input) = $0 { return input.feedIntent == .levain }
            return false
        }

        #expect(hasFeed)
        #expect(effects.count == 1)
    }

    @Test func buildLevainCompletedMarksPeak() {
        let effects = BakeCoordinator.sideEffects(
            forStep: .buildLevain,
            event: .completed,
            starterState: .active,
            feedDetails: nil,
            kitchenTempCelsius: 24
        )

        let hasPeakMark = effects.contains {
            if case let .markPeakOnLatestFeed(intent) = $0 { return intent == .levain }
            return false
        }

        #expect(hasPeakMark)
        #expect(effects.count == 1)
    }

    // MARK: - Refeed and Refrigerate

    @Test func refeedAndRefrigerateTransitionsToDormant() {
        let effects = BakeCoordinator.sideEffects(
            forStep: .refeedAndRefrigerate,
            event: .completed,
            starterState: .active,
            feedDetails: nil,
            kitchenTempCelsius: 22
        )

        let hasTransition = effects.contains {
            if case let .transitionLifecycle(result) = $0 { return result.newState == .dormant }
            return false
        }
        let hasStorageUpdate = effects.contains {
            if case let .updateStorageType(type) = $0 { return type == .fridge }
            return false
        }
        let hasFeed = effects.contains {
            if case let .logFeed(input) = $0 { return input.feedIntent == .postBake }
            return false
        }

        #expect(hasTransition)
        #expect(hasStorageUpdate)
        #expect(hasFeed)
    }

    // MARK: - Non-Starter Steps

    @Test func nonStarterStepProducesNoEffects() {
        let steps: [StepTypeID] = [.mix, .bulkFerment, .shape, .coldRetard, .bake, .preheat]

        for step in steps {
            let completed = BakeCoordinator.sideEffects(
                forStep: step, event: .completed,
                starterState: .active, feedDetails: nil, kitchenTempCelsius: 22
            )
            let started = BakeCoordinator.sideEffects(
                forStep: step, event: .started,
                starterState: .active, feedDetails: nil, kitchenTempCelsius: 22
            )
            #expect(completed.isEmpty, "Expected no effects for \(step) completed")
            #expect(started.isEmpty, "Expected no effects for \(step) started")
        }
    }

    // MARK: - Default Feed Details

    @Test func activateStarterDefaultsTo1_5_5() {
        let effects = BakeCoordinator.sideEffects(
            forStep: .activateStarter,
            event: .completed,
            starterState: .dormant,
            feedDetails: nil,
            kitchenTempCelsius: 22
        )

        let feed = effects.compactMap { e -> FeedLogInput? in
            if case let .logFeed(input) = e { return input }
            return nil
        }.first

        #expect(feed?.ratioStarter == 1)
        #expect(feed?.ratioFlour == 5)
        #expect(feed?.ratioWater == 5)
    }

    @Test func refeedDefaultsTo1_1_1() {
        let effects = BakeCoordinator.sideEffects(
            forStep: .refeedAndRefrigerate,
            event: .completed,
            starterState: .active,
            feedDetails: nil,
            kitchenTempCelsius: 22
        )

        let feed = effects.compactMap { e -> FeedLogInput? in
            if case let .logFeed(input) = e { return input }
            return nil
        }.first

        #expect(feed?.ratioStarter == 1)
        #expect(feed?.ratioFlour == 1)
        #expect(feed?.ratioWater == 1)
    }
}
