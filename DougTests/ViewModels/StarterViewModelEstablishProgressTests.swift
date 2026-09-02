@testable import Doug
import Foundation
import SwiftData
import Testing

@MainActor
@Suite(.serialized)
struct StarterViewModelEstablishProgressTests {
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

    // MARK: - Progressing

    @Test func theOpeningMixJustMovesToTheNextStep() throws {
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

        let outcome = viewModel.recordEstablishCheckIn(
            step: first,
            plan: plan,
            signals: nil,
            availability: nil,
            windows: [],
            profile: profile
        )

        #expect(outcome == .holdCourse)
        #expect(first.feedStatus == .completed)
        // The phase follows the step that's now current.
        #expect(plan.establishPhase == .dailyFeeds)
        #expect(plan.currentStepIndex > 0)
    }

    @Test func aFalseRiseLeavesThePlanUntouched() throws {
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
        // Complete the opening mix so we're in the daily-feeds phase.
        let first = try #require(sorted(plan).first)
        viewModel.recordEstablishCheckIn(
            step: first, plan: plan, signals: nil,
            availability: nil, windows: [], profile: profile
        )

        let daily = try #require(sorted(plan).first { $0.starterStepKind == .dailyFeed })
        let stepCountBefore = plan.feedSteps.count
        let phaseBefore = plan.establishPhase

        let outcome = viewModel.recordEstablishCheckIn(
            step: daily,
            plan: plan,
            signals: signals(bubbles: true, risen: true, smell: .cheesyOrFunky),
            availability: nil,
            windows: [],
            profile: profile
        )

        #expect(outcome == .falseRise)
        // The bloom is informational — it must not add, remove, or skip steps.
        #expect(plan.feedSteps.count == stepCountBefore)
        #expect(plan.establishPhase == phaseBefore)
        #expect(plan.revivalStatus == .active)
        #expect(daily.recordedSignals?.smell == .cheesyOrFunky)
    }

    @Test func gettingAheadDropsTheRestOfTheOutrunPhase() throws {
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
        viewModel.recordEstablishCheckIn(
            step: first, plan: plan, signals: nil,
            availability: nil, windows: [], profile: profile
        )

        let daily = try #require(sorted(plan).first { $0.starterStepKind == .dailyFeed })
        let totalBefore = plan.feedSteps.count

        let outcome = viewModel.recordEstablishCheckIn(
            step: daily,
            plan: plan,
            signals: signals(bubbles: true, smell: .yeastyBready),
            availability: nil,
            windows: [],
            profile: profile
        )

        #expect(outcome == .advancePhase(.twiceDailyFeeds))
        #expect(plan.establishPhase == .twiceDailyFeeds)
        // The remaining once-a-day feeds are no longer needed.
        let dailyStillPending = plan.feedSteps.count { $0.starterStepKind == .dailyFeed && $0.feedStatus == .pending }
        #expect(dailyStillPending == 0)
        #expect(plan.feedSteps.count < totalBefore)
    }

    @Test func aStalledStarterGetsExtraFeedsRatherThanAFailure() throws {
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
        viewModel.recordEstablishCheckIn(
            step: first, plan: plan, signals: nil,
            availability: nil, windows: [], profile: profile
        )

        let daily = try #require(sorted(plan).first { $0.starterStepKind == .dailyFeed })
        // Pretend we're well into the plan with nothing to show for it.
        daily.dayNumber = 8
        let countBefore = plan.feedSteps.count

        let outcome = viewModel.recordEstablishCheckIn(
            step: daily,
            plan: plan,
            signals: signals(),
            availability: nil,
            windows: [],
            profile: profile
        )

        guard case .stalled = outcome else {
            Issue.record("expected stalled, got \(outcome)")
            return
        }
        #expect(plan.feedSteps.count > countBefore)
        #expect(plan.revivalStatus == .active)
    }

    @Test func extraFeedsGetContiguousIndicesAndInheritTheirGrams() throws {
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
        let template = confirming

        // A confirming feed that didn't double should add more, not finish.
        let outcome = viewModel.recordEstablishCheckIn(
            step: confirming,
            plan: plan,
            signals: signals(bubbles: true, risen: true, smell: .pleasantlySour),
            availability: nil,
            windows: [],
            profile: profile
        )

        #expect(outcome == .needsMoreConfirming(extraFeeds: 2))
        let indices = sorted(plan).map(\.sequenceIndex)
        #expect(
            try indices == Array(#require(indices.min()) ... indices.max()!),
            "indices should not collide or gap: \(indices)"
        )

        let added = sorted(plan).filter { $0.sequenceIndex > template.sequenceIndex }
        #expect(added.count == 2)
        for step in added {
            #expect(step.starterStepKind == .readinessTest)
            #expect(step.retainStarterGrams == template.retainStarterGrams)
            #expect(step.addFlourGrams == template.addFlourGrams)
        }
    }

    @Test func rehydratingADriedCultureKeepsTheFlourStepThatFollowsIt() throws {
        // Regression: the opening phase used to advance straight to the
        // once-a-day stage, which deleted every remaining opening step — for a
        // dried culture that meant losing the flour feed entirely.
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
        let rehydrate = try #require(sorted(plan).first)
        #expect(rehydrate.starterStepKind == .rehydrate)
        let countBefore = plan.feedSteps.count

        viewModel.recordEstablishCheckIn(
            step: rehydrate, plan: plan, signals: nil,
            availability: nil, windows: [], profile: profile
        )

        #expect(plan.feedSteps.count == countBefore)
        let next = try #require(sorted(plan).first { $0.feedStatus == .pending })
        #expect(next.starterStepKind == .initialMix)
        #expect(plan.currentStepIndex == next.sequenceIndex)
        #expect(plan.establishPhase == .initialMix)
    }

    @Test func aScratchPlanReachesConfirmingByWalkingEveryStep() throws {
        // Walks the whole plan the way a user would, to catch any step that
        // silently strands the plan.
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

        var guardCount = 0
        while let step = sorted(plan).first(where: { $0.feedStatus == .pending }), guardCount < 30 {
            guardCount += 1
            // Report steady, unremarkable progress — no shortcuts, no stalls.
            let observed: StarterCheckInSignals? = step.sequenceIndex == 0
                ? nil
                : signals(bubbles: true, doubled: step.expectsPeak, smell: .pleasantlySour)
            let outcome = viewModel.recordEstablishCheckIn(
                step: step, plan: plan, signals: observed,
                availability: nil, windows: [], profile: profile
            )
            if outcome == .complete { break }
        }

        #expect(guardCount < 30, "plan never terminated")
        #expect(plan.revivalStatus == .completed)
        #expect(profile.hasStarter)
        #expect(profile.starterGeneration == 2)
    }
}
