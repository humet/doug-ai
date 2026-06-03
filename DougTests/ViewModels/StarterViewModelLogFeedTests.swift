@testable import Doug
import Foundation
import SwiftData
import Testing

@MainActor
@Suite(.serialized)
struct StarterViewModelLogFeedTests {
    /// Returns the container (which the caller MUST keep in scope — if it
    /// deallocates, its `mainContext` dangles and inserts trap) plus a
    /// freshly-inserted profile in the requested state.
    private func makeContainer(
        lifecycle: StarterLifecycleState = .dormant,
        storage: StarterStorageType = .fridge
    ) throws -> (ModelContainer, StarterProfile) {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: StarterProfile.self, StarterFeedLog.self,
            configurations: config
        )
        let profile = StarterProfile(storageType: storage)
        profile.starterLifecycleState = lifecycle
        container.mainContext.insert(profile)
        return (container, profile)
    }

    // MARK: - Auto-activate on activation feed

    @Test func loggingActivationFeedWhileDormantMovesToCounter() throws {
        let (container, profile) = try makeContainer(lifecycle: .dormant, storage: .fridge)
        let viewModel = StarterViewModel()

        viewModel.logFeed(modelContext: container.mainContext, profile: profile, intent: .activation)

        // Taking it out to wake it up should land on the counter, mid-activation.
        #expect(profile.starterLifecycleState == .activating)
        #expect(profile.starterStorageType == .counter)

        let logs = try container.mainContext.fetch(FetchDescriptor<StarterFeedLog>())
        #expect(logs.count == 1)
        #expect(logs.first?.starterFeedIntent == .activation)
    }

    @Test func loggingMaintenanceFeedWhileDormantStaysInFridge() throws {
        let (container, profile) = try makeContainer(lifecycle: .dormant, storage: .fridge)
        let viewModel = StarterViewModel()

        viewModel.logFeed(modelContext: container.mainContext, profile: profile, intent: .maintenance)

        // A fridge maintenance feed must not change where the starter lives.
        #expect(profile.starterLifecycleState == .dormant)
        #expect(profile.starterStorageType == .fridge)

        let logs = try container.mainContext.fetch(FetchDescriptor<StarterFeedLog>())
        #expect(logs.first?.starterFeedIntent == .maintenance)
    }

    @Test func loggingMaintenanceFeedWhileActiveReturnsToFridge() throws {
        let (container, profile) = try makeContainer(lifecycle: .active, storage: .counter)
        let viewModel = StarterViewModel()

        viewModel.logFeed(modelContext: container.mainContext, profile: profile, intent: .maintenance)

        // Fed for storage while out — it should go back in the fridge so the hero
        // can't keep showing "Counter / Active" after a fridge feed.
        #expect(profile.starterLifecycleState == .dormant)
        #expect(profile.starterStorageType == .fridge)
    }

    @Test func loggingMaintenanceFeedWhileActivatingReturnsToFridge() throws {
        let (container, profile) = try makeContainer(lifecycle: .activating, storage: .counter)
        let viewModel = StarterViewModel()

        viewModel.logFeed(modelContext: container.mainContext, profile: profile, intent: .maintenance)

        #expect(profile.starterLifecycleState == .dormant)
        #expect(profile.starterStorageType == .fridge)
    }

    @Test func loggingActivationFeedWhileActiveStaysActive() throws {
        let (container, profile) = try makeContainer(lifecycle: .active, storage: .counter)
        let viewModel = StarterViewModel()

        viewModel.logFeed(modelContext: container.mainContext, profile: profile, intent: .activation)

        // Already past activation — a refresh feed shouldn't knock it backwards.
        #expect(profile.starterLifecycleState == .active)
    }

    @Test func loggingLevainFeedWhileDormantDoesNotActivate() throws {
        let (container, profile) = try makeContainer(lifecycle: .dormant, storage: .fridge)
        let viewModel = StarterViewModel()

        viewModel.logFeed(modelContext: container.mainContext, profile: profile, intent: .levain)

        // Only counter/activation feeds imply taking the starter out of the fridge.
        #expect(profile.starterLifecycleState == .dormant)
        #expect(profile.starterStorageType == .fridge)
    }
}
