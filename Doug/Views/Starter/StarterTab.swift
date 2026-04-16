import SwiftUI
import SwiftData

struct StarterTab: View {
    @State private var viewModel = StarterViewModel()

    @Query(sort: \StarterFeedLog.timestamp, order: .reverse)
    private var feedLogs: [StarterFeedLog]

    @Query private var profiles: [StarterProfile]
    @Query private var availabilities: [UserAvailability]
    @Query private var windows: [UnavailableWindow]
    @Query(sort: \RevivalPlan.startDate, order: .reverse)
    private var revivalPlans: [RevivalPlan]

    @Environment(\.modelContext) private var modelContext

    private var profile: StarterProfile? { profiles.first }
    private var activeRevivalPlan: RevivalPlan? {
        revivalPlans.first(where: { $0.revivalStatus == .active })
    }

    var body: some View {
        NavigationStack {
            List {
                healthSection
                revivalSection
                nextFeedSection
                feedHistorySection
            }
            .navigationTitle("Starter")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        viewModel.showLogFeed = true
                    } label: {
                        Label("Log Feed", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $viewModel.showLogFeed) {
                LogFeedSheet(viewModel: viewModel, modelContext: modelContext)
            }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var healthSection: some View {
        Section {
            let status = viewModel.healthStatus(profile: profile, feedLogs: feedLogs)
            HStack {
                Image(systemName: healthIcon(status))
                    .foregroundStyle(healthColor(status))
                    .font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(healthLabel(status))
                        .font(.headline)
                    Text(healthDescription(status))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text("Health")
        }
    }

    @ViewBuilder
    private var revivalSection: some View {
        let status = viewModel.healthStatus(profile: profile, feedLogs: feedLogs)

        if status == .needsRevival {
            Section {
                if let plan = activeRevivalPlan {
                    NavigationLink {
                        RevivalPlanView(plan: plan)
                    } label: {
                        HStack {
                            Label("Revival in progress", systemImage: "arrow.trianglehead.2.clockwise")
                            Spacer()
                            if let bakeReady = plan.estimatedBakeReadyDate {
                                Text(bakeReady, style: .relative)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } else {
                    Button {
                        _ = viewModel.startRevival(
                            profile: profile,
                            availability: availabilities.first,
                            windows: Array(windows),
                            modelContext: modelContext
                        )
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

    @ViewBuilder
    private var nextFeedSection: some View {
        if let nextFeed = viewModel.nextFeedTime(
            profile: profile,
            feedLogs: feedLogs,
            availability: availabilities.first,
            windows: Array(windows),
            upcomingBakeStart: nil
        ) {
            Section {
                HStack {
                    Label("Next feed", systemImage: "clock")
                    Spacer()
                    Text(nextFeed, style: .relative)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Spacer()
                    Text(nextFeed, format: .dateTime.weekday(.wide).hour().minute())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var feedHistorySection: some View {
        if feedLogs.isEmpty {
            ContentUnavailableView(
                "No Feeds Logged",
                systemImage: "bubbles.and.sparkles",
                description: Text("Log your first starter feed to start tracking.")
            )
        } else {
            Section {
                ForEach(feedLogs) { log in
                    FeedLogRow(log: log) {
                        viewModel.markPeak(for: log, profile: profile, allLogs: feedLogs)
                    }
                }
            } header: {
                Text("Feed History")
            }
        }
    }

    // MARK: - Helpers

    private func healthIcon(_ status: StarterHealthStatus) -> String {
        switch status {
        case .readyToBake: "checkmark.circle.fill"
        case .needsFeed: "exclamationmark.circle.fill"
        case .needsRevival: "xmark.circle.fill"
        }
    }

    private func healthColor(_ status: StarterHealthStatus) -> Color {
        switch status {
        case .readyToBake: DougTheme.starterReady
        case .needsFeed: DougTheme.starterNeedsFeed
        case .needsRevival: DougTheme.starterNeedsRevival
        }
    }

    private func healthLabel(_ status: StarterHealthStatus) -> String {
        switch status {
        case .readyToBake: "Ready to Bake"
        case .needsFeed: "Needs a Feed"
        case .needsRevival: "Needs Revival"
        }
    }

    private func healthDescription(_ status: StarterHealthStatus) -> String {
        switch status {
        case .readyToBake: "Your starter is active and ready for a levain build."
        case .needsFeed: "Feed your starter before planning a bake."
        case .needsRevival: "Multiple feeds needed to restore strength."
        }
    }
}

// MARK: - Feed Log Row

struct FeedLogRow: View {
    let log: StarterFeedLog
    let onMarkPeak: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(log.ratioDescription)
                    .font(.headline)
                Spacer()
                Text(log.timestamp, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Label(log.flourType, systemImage: "leaf")
                    .font(.caption)
                Label("\(Int(log.kitchenTemperatureCelsius))°C", systemImage: "thermometer.medium")
                    .font(.caption)
                Spacer()

                if let peak = log.timeToPeakMinutes {
                    Label("\(Int(peak))m to peak", systemImage: "chart.line.uptrend.xyaxis")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else if log.peakTimestamp == nil {
                    Button("Mark Peak", action: onMarkPeak)
                        .font(.caption)
                        .buttonStyle(.bordered)
                }
            }
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Log Feed Sheet

struct LogFeedSheet: View {
    @Bindable var viewModel: StarterViewModel
    let modelContext: ModelContext

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Ratio") {
                    Stepper("Starter: \(viewModel.feedRatioStarter)", value: $viewModel.feedRatioStarter, in: 1...10)
                    Stepper("Flour: \(viewModel.feedRatioFlour)", value: $viewModel.feedRatioFlour, in: 1...20)
                    Stepper("Water: \(viewModel.feedRatioWater)", value: $viewModel.feedRatioWater, in: 1...20)
                }

                Section("Details") {
                    Picker("Flour type", selection: $viewModel.feedFlourType) {
                        Text("White").tag("white")
                        Text("Whole Wheat").tag("whole wheat")
                        Text("Rye").tag("rye")
                    }

                    HStack {
                        Text("Kitchen temp")
                        Spacer()
                        Text("\(Int(viewModel.feedKitchenTemp))°C")
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $viewModel.feedKitchenTemp, in: 16...32, step: 1)
                }

                Section {
                    Text("Ratio: \(viewModel.feedRatioStarter):\(viewModel.feedRatioFlour):\(viewModel.feedRatioWater)")
                        .font(.headline)
                } header: {
                    Text("Summary")
                }
            }
            .navigationTitle("Log Feed")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        viewModel.logFeed(modelContext: modelContext)
                    }
                }
            }
        }
    }
}

#Preview {
    StarterTab()
        .modelContainer(for: StarterFeedLog.self, inMemory: true)
}
