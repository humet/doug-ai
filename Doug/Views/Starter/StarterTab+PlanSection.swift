import SwiftUI

/// The Starter tab's plan section: either a revival for an existing starter,
/// or the flow for building a new one.
extension StarterTab {
    // MARK: - Starter Plan (revival, or building a new one)

    @ViewBuilder
    var starterPlanSection: some View {
        let status = viewModel.healthStatus(profile: profile, feedLogs: liveFeedLogs)

        if lifecycleState == .establishing || status == .establishing {
            newStarterSection
        } else if status == .needsRevival {
            revivalSection
        }
    }

    var newStarterSection: some View {
        Section {
            if let plan = activeStarterPlan {
                NavigationLink {
                    RevivalPlanView(plan: plan)
                } label: {
                    RevivalInProgressRow(plan: plan)
                }
                .listRowBackground(Color.accentColor.opacity(0.08))
            } else {
                Button {
                    viewModel.showStartNewStarter = true
                } label: {
                    Label("Start a Starter", systemImage: "sparkles")
                }
            }
        } header: {
            Text("New Starter")
        } footer: {
            Text(activeStarterPlan == nil
                ? "Build one from flour and water, wake a dried culture, or start from a friend's starter."
                : "Follow the plan — Doug adjusts it based on what you report seeing.")
        }
    }

    var revivalSection: some View {
        Section {
            if let plan = activeRevivalPlan {
                NavigationLink {
                    RevivalPlanView(plan: plan)
                } label: {
                    RevivalInProgressRow(plan: plan)
                }
                .listRowBackground(Color.accentColor.opacity(0.08))
            } else {
                Button {
                    viewModel.showStartRevival = true
                } label: {
                    Label("Start Revival Plan", systemImage: "arrow.trianglehead.2.clockwise")
                }
            }
        } header: {
            Text("Revival")
        } footer: {
            Text("Your starter needs multiple feeds before it's ready to bake.")
        }
    }
}
