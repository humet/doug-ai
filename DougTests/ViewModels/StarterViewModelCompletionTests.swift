@testable import Doug
import Foundation
import SwiftData
import Testing

@MainActor
@Suite(.serialized)
struct StarterViewModelCompletionTests {
    /// Keep the container in scope for the whole test — a released container
    /// takes its objects with it.
    private func makeContainer(
        lifecycle: StarterLifecycleState = .dormant,
        hasStarter: Bool = false
    ) throws -> (ModelContainer, ModelContext, StarterProfile) {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: StarterProfile.self, StarterFeedLog.self, RevivalPlan.self, RevivalFeedStep.self,
            UserAvailability.self, UnavailableWindow.self,
            configurations: config
        )
        let context = ModelContext(container)
        let profile = StarterProfile(storageType: .fridge)
        profile.starterLifecycleState = lifecycle
        profile.hasStarter = hasStarter
        context.insert(profile)
        return (container, context, profile)
    }

    private func request(
        _ origin: StarterOrigin,
        seedGrams: Double? = nil
    ) -> StarterViewModel.NewStarterRequest {
        StarterViewModel.NewStarterRequest(
            origin: origin,
            seedGrams: seedGrams ?? StarterOriginPlanner.defaultSeedGrams(for: origin),
            flourType: StarterOriginPlanner.recommendedFlour(for: origin),
            kitchenTempC: 22
        )
    }

    private func signals(
        bubbles: Bool = false,
        risen: Bool = false,
        doubled: Bool = false,
        smell: StarterSmell = .nothing
    ) -> StarterCheckInSignals {
        StarterCheckInSignals(hasBubbles: bubbles, hasRisen: risen, hasDoubled: doubled, smell: smell)
    }

    private func sorted(_ plan: RevivalPlan) -> [RevivalFeedStep] {
        plan.feedSteps.sorted { $0.sequenceIndex < $1.sequenceIndex }
    }

    // MARK: - Completing

    @Test func aGiftedStarterCompletesOnOneCleanDouble() throws {
        let (container, context, profile) = try makeContainer()
        _ = container
        let viewModel = StarterViewModel()

        let plan = viewModel.startNewStarter(
            request(.freshGift),
            availability: nil,
            windows: [],
            profile: profile,
            modelContext: context
        )
        let confirming = try #require(sorted(plan).first { $0.starterStepKind == .readinessTest })
        confirming.peakTimestamp = Date()

        let outcome = viewModel.recordEstablishCheckIn(
            step: confirming,
            plan: plan,
            signals: signals(bubbles: true, doubled: true, smell: .pleasantlySour),
            availability: nil,
            windows: [],
            profile: profile
        )

        #expect(outcome == .complete)
        #expect(plan.revivalStatus == .completed)
        #expect(profile.hasStarter)
        #expect(profile.starterLifecycleState == .active)
        #expect(profile.starterHealthStatus == .readyToBake)
    }

    @Test func completingBumpsTheGenerationAndClearsInheritedAverages() throws {
        let (container, context, profile) = try makeContainer()
        _ = container
        profile.averageTimeToPeakMinutes = 900
        profile.activePeakAverageMinutes = 900

        let viewModel = StarterViewModel()
        let plan = viewModel.startNewStarter(
            request(.freshGift),
            availability: nil,
            windows: [],
            profile: profile,
            modelContext: context
        )
        let confirming = try #require(sorted(plan).first { $0.starterStepKind == .readinessTest })

        viewModel.recordEstablishCheckIn(
            step: confirming,
            plan: plan,
            signals: signals(bubbles: true, doubled: true, smell: .pleasantlySour),
            availability: nil,
            windows: [],
            profile: profile
        )

        #expect(profile.starterGeneration == 2)
        #expect(profile.starterBornAt != nil)
        // The old starter's slow timings must not follow it.
        #expect(profile.averageTimeToPeakMinutes == nil)
        #expect(profile.activePeakAverageMinutes == nil)
    }

    @Test func scratchNeedsTwoCleanDoublesBeforeItCounts() throws {
        let (container, context, profile) = try makeContainer()
        _ = container
        let viewModel = StarterViewModel()

        let plan = viewModel.startNewStarter(
            request(.fromScratch),
            availability: nil,
            windows: [],
            profile: profile,
            modelContext: context
        )
        let tests = sorted(plan).filter { $0.starterStepKind == .readinessTest }
        #expect(tests.count >= 2)

        let firstOutcome = viewModel.recordEstablishCheckIn(
            step: tests[0],
            plan: plan,
            signals: signals(bubbles: true, doubled: true, smell: .pleasantlySour),
            availability: nil,
            windows: [],
            profile: profile
        )
        #expect(firstOutcome == .holdCourse)
        #expect(plan.revivalStatus == .active)
        #expect(profile.starterGeneration == 1)

        let secondOutcome = viewModel.recordEstablishCheckIn(
            step: tests[1],
            plan: plan,
            signals: signals(bubbles: true, doubled: true, smell: .pleasantlySour),
            availability: nil,
            windows: [],
            profile: profile
        )
        #expect(secondOutcome == .complete)
        #expect(profile.starterGeneration == 2)
    }

    @Test func aBrokenRunOfDoublesStartsCountingAgain() throws {
        let (container, context, profile) = try makeContainer()
        _ = container
        let viewModel = StarterViewModel()

        let plan = viewModel.startNewStarter(
            request(.fromScratch),
            availability: nil,
            windows: [],
            profile: profile,
            modelContext: context
        )
        let tests = sorted(plan).filter { $0.starterStepKind == .readinessTest }

        viewModel.recordEstablishCheckIn(
            step: tests[0], plan: plan,
            signals: signals(bubbles: true, doubled: true, smell: .pleasantlySour),
            availability: nil, windows: [], profile: profile
        )
        #expect(plan.consecutiveDoubles == 1)

        // A miss resets the run — "reliably" is the whole point of the test.
        viewModel.recordEstablishCheckIn(
            step: tests[1], plan: plan,
            signals: signals(bubbles: true, risen: true, smell: .pleasantlySour),
            availability: nil, windows: [], profile: profile
        )
        #expect(plan.consecutiveDoubles == 0)
        #expect(plan.revivalStatus == .active)
    }

    @Test func completingSeedsOneRealPeakReadingForTheScheduler() throws {
        let (container, context, profile) = try makeContainer()
        _ = container
        let viewModel = StarterViewModel()

        let plan = viewModel.startNewStarter(
            request(.freshGift),
            availability: nil,
            windows: [],
            profile: profile,
            modelContext: context
        )
        let confirming = try #require(sorted(plan).first { $0.starterStepKind == .readinessTest })
        confirming.startedAt = Date().addingTimeInterval(-5 * 3600)
        confirming.peakTimestamp = Date()

        viewModel.recordEstablishCheckIn(
            step: confirming,
            plan: plan,
            signals: signals(bubbles: true, doubled: true, smell: .pleasantlySour),
            availability: nil,
            windows: [],
            profile: profile
        )

        let logs = try context.fetch(FetchDescriptor<StarterFeedLog>())
        let seeded = try #require(logs.first)
        #expect(seeded.starterFeedIntent == .activation)
        // Stamped with the new generation, so it survives the generation filter.
        #expect(seeded.starterGeneration == profile.starterGeneration)
        let minutes = try #require(seeded.timeToPeakMinutes)
        #expect(abs(minutes - 300) < 5)
    }

    // MARK: - Generations

    @Test func retiredReadingsAreExcludedFromTheCurrentStarter() throws {
        let (container, context, profile) = try makeContainer(hasStarter: true)
        _ = container
        let viewModel = StarterViewModel()

        // A junk reading from the starter that died — exactly the kind that
        // wipes out every available bake slot if it reaches the averages.
        let old = StarterFeedLog(
            timestamp: Date().addingTimeInterval(-20 * 86400),
            ratioStarter: 1, ratioFlour: 5, ratioWater: 5,
            kitchenTemperatureCelsius: 22,
            feedIntent: .activation,
            starterGeneration: 1
        )
        context.insert(old)

        profile.starterGeneration = 2
        let fresh = StarterFeedLog(
            timestamp: Date(),
            ratioStarter: 1, ratioFlour: 5, ratioWater: 5,
            kitchenTemperatureCelsius: 22,
            feedIntent: .activation,
            starterGeneration: 2
        )
        context.insert(fresh)

        let live = viewModel.currentGeneration([fresh, old], profile: profile)
        #expect(live.count == 1)
        #expect(live.first === fresh)
    }

    @Test func withNoProfileEveryLogCounts() throws {
        let (container, context, _) = try makeContainer()
        _ = container
        let viewModel = StarterViewModel()
        let log = StarterFeedLog(
            timestamp: Date(),
            ratioStarter: 1, ratioFlour: 5, ratioWater: 5,
            kitchenTemperatureCelsius: 22
        )
        context.insert(log)

        #expect(viewModel.currentGeneration([log], profile: nil).count == 1)
    }

    // MARK: - Cancelling

    @Test func cancellingReturnsTheProfileToDormant() throws {
        let (container, context, profile) = try makeContainer()
        _ = container
        let viewModel = StarterViewModel()

        let plan = viewModel.startNewStarter(
            request(.fromScratch),
            availability: nil,
            windows: [],
            profile: profile,
            modelContext: context
        )
        viewModel.cancelNewStarter(plan: plan, profile: profile)

        #expect(plan.revivalStatus == .cancelled)
        #expect(profile.starterLifecycleState == .dormant)
        // Still no starter — cancelling doesn't conjure one.
        #expect(!profile.hasStarter)
    }
}
