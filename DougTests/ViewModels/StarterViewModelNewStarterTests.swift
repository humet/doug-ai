@testable import Doug
import Foundation
import SwiftData
import Testing

@MainActor
@Suite(.serialized)
struct StarterViewModelNewStarterTests {
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

    // MARK: - Starting

    @Test func startingAPlanPersistsStepsAndMovesTheProfileToEstablishing() throws {
        let (container, context, profile) = try makeContainer()
        _ = container
        let viewModel = StarterViewModel()

        let plan = viewModel.startNewStarter(
            request(.driedCulture),
            availability: nil,
            windows: [],
            profile: profile,
            modelContext: context
        )

        #expect(plan.isEstablishingNewStarter)
        #expect(plan.starterOrigin == .driedCulture)
        #expect(!plan.feedSteps.isEmpty)
        #expect(plan.targetStepCount == plan.feedSteps.count)
        #expect(plan.estimatedBakeReadyDate != nil)
        #expect(profile.starterLifecycleState == .establishing)
        // A new starter lives on the counter, not the fridge.
        #expect(profile.starterStorageType == .counter)
    }

    @Test func startingAPlanDoesNotYetClaimTheUserHasAStarter() throws {
        let (container, context, profile) = try makeContainer()
        _ = container
        let viewModel = StarterViewModel()

        viewModel.startNewStarter(
            request(.fromScratch),
            availability: nil,
            windows: [],
            profile: profile,
            modelContext: context
        )

        // There's a jar, but nothing you could bake with yet.
        #expect(!profile.hasStarter)
        #expect(profile.starterGeneration == 1)
    }

    @Test func everyStepGetsInstructionCopy() throws {
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

        for step in plan.feedSteps {
            #expect(!(step.instructionTitle ?? "").isEmpty)
            #expect(!(step.instructionBody ?? "").isEmpty)
            #expect(step.dayNumber != nil)
            #expect(step.establishPhase != nil)
        }
    }

    @Test func theOpeningScratchStepExpectsNoPeak() throws {
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

        let first = try #require(sorted(plan).first)
        #expect(first.starterStepKind == .initialMix)
        #expect(!first.expectsPeak)
        #expect(first.retainStarterGrams == 0)
    }

    // MARK: - Declaring a Starter Dead

    @Test func markingAStarterDeadStopsItLookingAliveAndClearsItsAverages() throws {
        let (container, _, profile) = try makeContainer(lifecycle: .active, hasStarter: true)
        _ = container
        profile.averageTimeToPeakMinutes = 300
        profile.activePeakAverageMinutes = 280

        let viewModel = StarterViewModel()
        viewModel.markStarterDead(profile: profile)

        #expect(!profile.hasStarter)
        #expect(profile.starterLifecycleState == .dormant)
        // A dead starter's timings must not be inherited by its replacement.
        #expect(profile.averageTimeToPeakMinutes == nil)
        #expect(profile.activePeakAverageMinutes == nil)
    }

    @Test func aDeadStarterCanBeReplacedStraightAway() throws {
        let (container, context, profile) = try makeContainer(lifecycle: .active, hasStarter: true)
        _ = container
        let viewModel = StarterViewModel()

        // The pink-starter path: declare it dead, then start again.
        viewModel.markStarterDead(profile: profile)
        let plan = viewModel.startNewStarter(
            request(.driedCulture),
            availability: nil,
            windows: [],
            profile: profile,
            modelContext: context
        )

        #expect(plan.isEstablishingNewStarter)
        #expect(profile.starterLifecycleState == .establishing)
    }
}
