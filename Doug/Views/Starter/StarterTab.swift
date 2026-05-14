import Combine
import SwiftData
import SwiftUI

struct StarterTab: View {
    @State private var viewModel = StarterViewModel()

    @Query(sort: \StarterFeedLog.timestamp, order: .reverse)
    private var feedLogs: [StarterFeedLog]

    @Query private var profiles: [StarterProfile]
    @Query private var availabilities: [UserAvailability]
    @Query private var windows: [UnavailableWindow]
    @Query(sort: \RevivalPlan.startDate, order: .reverse)
    private var revivalPlans: [RevivalPlan]
    @Query(sort: \Schedule.createdAt, order: .reverse)
    private var schedules: [Schedule]

    @Environment(\.modelContext) private var modelContext
    @State private var showCoachChat = false
    @State private var feedLogToDelete: StarterFeedLog?
    @State private var now = Date()

    private var profile: StarterProfile? {
        profiles.first
    }

    private var activeRevivalPlan: RevivalPlan? {
        revivalPlans.first(where: { $0.revivalStatus == .active })
    }

    private var activeBake: Schedule? {
        schedules.first { $0.scheduleStatus == .active }
    }

    private var upcomingBakeStart: Date? {
        let candidates = schedules.filter {
            $0.scheduleStatus == .planning || $0.scheduleStatus == .active
        }
        let levainStarts = candidates.compactMap { schedule in
            schedule.steps
                .first(where: { $0.stepTypeID == StepTypeID.buildLevain.rawValue })?
                .computedStartTime
        }
        return levainStarts.filter { $0 > now }.min()
    }

    private var upcomingRecipe: Recipe? {
        schedules
            .first { $0.scheduleStatus == .planning || $0.scheduleStatus == .active }
            .map { $0.recipe }
    }

    private var levainBuild: LevainBuildCalculator.Result? {
        guard let recipe = upcomingRecipe else { return nil }
        let kitchenTemp = feedLogs.first?.kitchenTemperatureCelsius ?? 22
        return LevainBuildCalculator.calculate(.init(
            levainGramsNeeded: recipe.ingredients.levainGrams,
            baseRatio: recipe.levainBuildRatio,
            referenceTemp: recipe.referenceTemperatureCelsius,
            kitchenTemp: kitchenTemp
        ))
    }

    private var hasRecentLevainFeed: Bool {
        guard let latest = feedLogs.first,
              latest.starterFeedIntent == .levain,
              Date().timeIntervalSince(latest.timestamp) < 12 * 3600 else { return false }
        return true
    }

    private var currentSuggestion: FeedSuggestion? {
        viewModel.feedSuggestion(
            profile: profile,
            feedLogs: feedLogs,
            availability: availabilities.first,
            windows: Array(windows),
            upcomingBakeStart: upcomingBakeStart
        )
    }

    private var lifecycleState: StarterLifecycleState {
        profile?.starterLifecycleState ?? .dormant
    }

    private var risingFeed: StarterFeedLog? {
        feedLogs.first {
            ($0.starterFeedIntent == .activation || $0.starterFeedIntent == .levain)
                && $0.peakTimestamp == nil
        }
    }

    var body: some View {
        NavigationStack {
            List {
                lifecycleSection
                levainGuidanceSection
                whatsNextSection
                revivalSection
                feedHistorySection
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("Starter")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showCoachChat = true
                    } label: {
                        Image(systemName: "bubble.left.and.text.bubble.right")
                    }
                    .accessibilityLabel("Coach")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        viewModel.showLogFeed = true
                    } label: {
                        Label("Log Feed", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showCoachChat) {
                CoachChatView(
                    schedule: nil,
                    scheduleViewModel: nil,
                    starterProfile: profile,
                    feedLogs: Array(feedLogs),
                    unavailableWindows: Array(windows)
                )
            }
            .sheet(isPresented: $viewModel.showLogFeed) {
                LogFeedSheet(viewModel: viewModel, modelContext: modelContext, profile: profile)
            }
            .sheet(item: $viewModel.editingFeedLog) { log in
                EditFeedLogSheet(log: log, profile: profile, allLogs: Array(feedLogs), viewModel: viewModel)
            }
            .alert("Delete Feed Log?", isPresented: Binding(
                get: { feedLogToDelete != nil },
                set: { if !$0 { feedLogToDelete = nil } }
            )) {
                Button("Delete", role: .destructive) {
                    if let log = feedLogToDelete {
                        viewModel.deleteFeedLog(
                            log,
                            modelContext: modelContext,
                            profile: profile,
                            feedLogs: Array(feedLogs)
                        )
                    }
                    feedLogToDelete = nil
                }
                Button("Cancel", role: .cancel) {
                    feedLogToDelete = nil
                }
            } message: {
                Text("This feed entry will be permanently removed.")
            }
            .sheet(isPresented: $viewModel.showStartRevival) {
                StartRevivalSheet(
                    viewModel: viewModel,
                    profile: profile,
                    availability: availabilities.first,
                    windows: Array(windows)
                )
            }
            .sheet(isPresented: $viewModel.showPostBake) {
                PostBakeSheet(viewModel: viewModel, modelContext: modelContext, profile: profile)
            }
            .task {
                if let profile {
                    viewModel.evaluateLifecycle(profile: profile, feedLogs: Array(feedLogs))
                }
            }
            .task(id: currentSuggestion?.time) {
                await viewModel.syncFeedReminder(
                    nextFeed: currentSuggestion?.time,
                    upcomingBakeStart: upcomingBakeStart
                )
            }
            .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { tick in
                now = tick
            }
        }
    }

    // MARK: - Lifecycle Status

    private var lifecycleSection: some View {
        Section {
            LifecycleStatusRow(
                state: lifecycleState,
                icon: lifecycleIcon,
                color: lifecycleColor,
                title: lifecycleTitle,
                subtitle: lifecycleSubtitle(now: now)
            )

            lifecycleActions
        } header: {
            Text("Starter")
        }
    }

    @ViewBuilder
    private var lifecycleActions: some View {
        if let bake = activeBake {
            HStack(spacing: 8) {
                Image(systemName: "oven")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Bake in progress")
                        .font(.subheadline.weight(.medium))
                    Text(bake.recipe.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            lifecycleActionsContent
        }
    }

    @ViewBuilder
    private var lifecycleActionsContent: some View {
        switch lifecycleState {
        case .dormant:
            Button {
                viewModel.showLogFeed = true
            } label: {
                Label("Log Maintenance Feed", systemImage: "snowflake")
            }
            Button {
                if let profile {
                    viewModel.activate(profile: profile)
                }
            } label: {
                Label("Activate for Bake", systemImage: "flame")
            }
            .tint(.orange)
        case .activating:
            if risingFeed != nil {
                Button {
                    if let feed = risingFeed {
                        viewModel.markPeak(for: feed, profile: profile, allLogs: Array(feedLogs))
                    }
                } label: {
                    Label("Mark Peak", systemImage: "chart.line.uptrend.xyaxis")
                }
                .tint(.green)
            } else {
                Button {
                    viewModel.showLogFeed = true
                } label: {
                    Label("Log Activation Feed", systemImage: "flame")
                }
                .tint(.orange)
            }
            Button {
                if let profile {
                    viewModel.refrigerate(profile: profile)
                }
            } label: {
                Label("Put Back in Fridge", systemImage: "snowflake")
            }
        case .active:
            Button {
                viewModel.showPostBake = true
            } label: {
                Label("Feed & Refrigerate", systemImage: "snowflake")
            }
        case .reviving:
            EmptyView()
        }
    }

    // MARK: - Levain Build Guidance

    @ViewBuilder
    private var levainGuidanceSection: some View {
        if let recipe = upcomingRecipe,
           let build = levainBuild,
           (lifecycleState == .active || lifecycleState == .activating),
           !hasRecentLevainFeed,
           activeBake == nil
        {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        Image(systemName: "bubbles.and.sparkles")
                            .font(.title3)
                            .foregroundStyle(.green)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Build Levain for \(recipe.name)")
                                .font(.subheadline.bold())
                            let ratio = build.ratio
                            Text("\(ratio.starter):\(ratio.flour):\(ratio.water) adjusted for \(Int(feedLogs.first?.kitchenTemperatureCelsius ?? 22))°C")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Keep \(Int(build.starterGrams))g starter")
                            Text("Add \(Int(build.flourGrams))g flour + \(Int(build.waterGrams))g water")
                        }
                        .font(.subheadline)

                        Spacer()

                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(Int(build.totalGrams))g total")
                                .font(.subheadline.bold())
                            Text("~\(String(format: "%.0f", build.estimatedPeakHours))h to peak")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Button {
                        let kitchenTemp = feedLogs.first?.kitchenTemperatureCelsius ?? 22
                        viewModel.prepareLevainBuild(for: recipe, kitchenTemp: kitchenTemp)
                        viewModel.showLogFeed = true
                    } label: {
                        Label("Log Levain Build", systemImage: "plus.circle.fill")
                    }
                    .tint(.green)
                }
            } header: {
                Text("Levain Build")
            } footer: {
                Text("Recipe needs \(Int(recipe.ingredients.levainGrams))g levain — extra goes to the fridge as maintenance.")
            }
        }
    }

    // MARK: - What's Next (unified section)

    @ViewBuilder
    private var whatsNextSection: some View {
        if lifecycleState == .dormant, let bakeStart = upcomingBakeStart {
            bakeAwarenessContent(bakeStart: bakeStart)
        } else if lifecycleState == .dormant, upcomingBakeStart == nil {
            PlanAheadSection(
                profile: profile,
                feedLogs: Array(feedLogs),
                availabilities: Array(availabilities),
                windows: Array(windows)
            )
        } else if activeRevivalPlan == nil, let suggestion = currentSuggestion {
            suggestionContent(suggestion)
        }
    }

    private func bakeAwarenessContent(bakeStart: Date) -> some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: "calendar.badge.clock")
                    .foregroundStyle(.orange)
                    .font(.title3)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Upcoming bake needs active starter")
                        .font(.subheadline.bold())
                    Text(
                        "Feed your starter on the counter by \(bakeStart.addingTimeInterval(-6 * 3600), format: .dateTime.weekday(.wide).hour().minute())"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            Button {
                if let profile {
                    viewModel.activate(profile: profile)
                }
            } label: {
                Label("Activate Now", systemImage: "flame")
            }
            .tint(.orange)
        } header: {
            Text("What's Next")
        }
    }


    private func suggestionContent(_ suggestion: FeedSuggestion) -> some View {
        Section {
            HStack {
                Label {
                    Text(suggestion.reason)
                } icon: {
                    Image(systemName: suggestion.intent == .activation ? "flame" : "clock")
                }
                Spacer()
                RelativeTimeLabel(date: suggestion.time)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Text(suggestion.time, format: .dateTime.weekday(.wide).hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("What's Next")
        } footer: {
            if suggestion.urgency == .urgent {
                Text("This is getting urgent — don't wait too long.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }


    // MARK: - Revival

    @ViewBuilder
    private var revivalSection: some View {
        let status = viewModel.healthStatus(profile: profile, feedLogs: feedLogs)

        if status == .needsRevival {
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

    // MARK: - Feed History

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
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            feedLogToDelete = log
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        Button {
                            viewModel.editingFeedLog = log
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        .tint(.blue)
                    }
                }
            } header: {
                Text("Feed History")
            }
        }
    }

    // MARK: - Lifecycle Helpers

    private var lifecycleIcon: String {
        switch lifecycleState {
        case .dormant:
            let status = viewModel.healthStatus(profile: profile, feedLogs: feedLogs)
            return healthIcon(status)
        case .activating: return "flame.fill"
        case .active: return "checkmark.circle.fill"
        case .reviving: return "arrow.triangle.2.circlepath.circle.fill"
        }
    }

    private var lifecycleColor: Color {
        switch lifecycleState {
        case .dormant:
            let status = viewModel.healthStatus(profile: profile, feedLogs: feedLogs)
            return healthColor(status)
        case .activating: return .orange
        case .active: return DougTheme.starterReady
        case .reviving: return .accentColor
        }
    }

    private var lifecycleTitle: String {
        switch lifecycleState {
        case .dormant: "In the Fridge"
        case .activating: risingFeed != nil ? "Waking Up" : "Activating"
        case .active: "Ready to Bake!"
        case .reviving: "In Revival"
        }
    }

    private func lifecycleSubtitle(now: Date) -> String {
        switch lifecycleState {
        case .dormant:
            if let lastFeed = feedLogs.first {
                let days = Int(now.timeIntervalSince(lastFeed.timestamp) / 86400)
                return "Last fed \(days) day\(days == 1 ? "" : "s") ago"
            }
            return "No feeds logged yet"
        case .activating:
            if let feed = risingFeed {
                let hours = Int(now.timeIntervalSince(feed.timestamp) / 3600)
                return "Rising on the counter — \(hours)h since feed"
            }
            return "Feed your starter on the counter to wake it up"
        case .active:
            let hours = Int(now.timeIntervalSince(profile?.stateChangedAt ?? now) / 3600)
            return "Active for \(hours)h — build your levain or feed & refrigerate"
        case .reviving:
            return "Your starter is rebuilding strength. Follow the revival plan below."
        }
    }

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
}

// MARK: - Lifecycle Status Row

private struct LifecycleStatusRow: View {
    let state: StarterLifecycleState
    let icon: String
    let color: Color
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .font(.title2)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .padding(.vertical, 4)
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
                intentBadge
                Spacer()
                RelativeTimeLabel(date: log.timestamp)
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
                } else if log.peakTimestamp == nil, log.starterFeedIntent == .activation {
                    Button("Mark Peak", action: onMarkPeak)
                        .font(.caption)
                        .buttonStyle(.bordered)
                }
            }
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var intentBadge: some View {
        switch log.starterFeedIntent {
        case .activation:
            Label("Counter", systemImage: "flame")
                .font(.caption2)
                .foregroundStyle(.orange)
        case .levain:
            Label("Levain", systemImage: "bubbles.and.sparkles")
                .font(.caption2)
                .foregroundStyle(.green)
        case .postBake:
            Label("Post-bake", systemImage: "arrow.uturn.down")
                .font(.caption2)
                .foregroundStyle(.secondary)
        case .maintenance:
            Label("Fridge", systemImage: "snowflake")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Revival In-Progress Row

private struct RevivalInProgressRow: View {
    let plan: RevivalPlan

    private var sortedSteps: [RevivalFeedStep] {
        plan.feedSteps.sorted { $0.sequenceIndex < $1.sequenceIndex }
    }

    private var currentStep: RevivalFeedStep? {
        sortedSteps.first(where: { $0.sequenceIndex == plan.currentStepIndex })
            ?? sortedSteps.last
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.trianglehead.2.clockwise")
                .font(.title3)
                .foregroundStyle(.tint)
                .symbolEffect(.rotate, options: .repeat(.continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(titleText)
                    .font(.subheadline.bold())
                if let subtitle = subtitleText {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if let bakeReady = plan.estimatedBakeReadyDate {
                RelativeTimeLabel(date: bakeReady)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private var titleText: String {
        let total = sortedSteps.count
        let current = min(plan.currentStepIndex + 1, max(total, 1))
        return "Revival — Step \(current) of \(total)"
    }

    private var subtitleText: String? {
        guard let step = currentStep else { return nil }
        switch step.feedStatus {
        case .pending:
            if step.scheduledTime > Date() {
                return "Feed at \(step.scheduledTime.formatted(date: .omitted, time: .shortened))"
            }
            return "Ready to feed"
        case .inProgress:
            let peak = (step.startedAt ?? step.scheduledTime)
                .addingTimeInterval(step.expectedPeakMinutes * 60)
            return "Rising — peak around \(peak.formatted(date: .omitted, time: .shortened))"
        case .peaked:
            return "Peaked — resting until next feed"
        case .completed:
            return "Feed complete"
        }
    }
}

#Preview {
    StarterTab()
        .modelContainer(for: StarterFeedLog.self, inMemory: true)
}
