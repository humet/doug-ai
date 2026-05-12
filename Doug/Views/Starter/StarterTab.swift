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

    private var profile: StarterProfile? {
        profiles.first
    }

    private var activeRevivalPlan: RevivalPlan? {
        revivalPlans.first(where: { $0.revivalStatus == .active })
    }

    /// The upcoming bake's levain-build start time, if any, used to line up feed suggestions.
    private var upcomingBakeStart: Date? {
        let now = Date()
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

    private var currentSuggestion: FeedSuggestion? {
        viewModel.feedSuggestion(
            profile: profile,
            feedLogs: feedLogs,
            availability: availabilities.first,
            windows: Array(windows),
            upcomingBakeStart: upcomingBakeStart
        )
    }

    private var nextFeed: Date? {
        currentSuggestion?.time
    }

    private var lifecycleState: StarterLifecycleState {
        profile?.starterLifecycleState ?? .dormant
    }

    var body: some View {
        NavigationStack {
            List {
                lifecycleSection
                bakeAwarenessSection
                revivalSection
                suggestionSection
                feedHistorySection
            }
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
            .task(id: nextFeed) {
                await viewModel.syncFeedReminder(
                    nextFeed: nextFeed,
                    upcomingBakeStart: upcomingBakeStart
                )
            }
        }
    }

    // MARK: - Sections

    private var lifecycleSection: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: lifecycleIcon)
                    .foregroundStyle(lifecycleColor)
                    .font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(lifecycleTitle)
                        .font(.headline)
                    Text(lifecycleSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)

            lifecycleActions
        } header: {
            Text("Starter")
        }
    }

    @ViewBuilder
    private var lifecycleActions: some View {
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
            let risingFeed = feedLogs.first { $0.starterFeedIntent == .activation && $0.peakTimestamp == nil }
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
                    if let result = StarterStateMachine.refrigerate(currentState: profile.starterLifecycleState) {
                        profile.starterLifecycleState = result.newState
                    }
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
        case .dormant: return "In the Fridge"
        case .activating:
            let risingFeed = feedLogs.first { $0.starterFeedIntent == .activation && $0.peakTimestamp == nil }
            return risingFeed != nil ? "Waking Up" : "Activating"
        case .active: return "Ready to Bake!"
        case .reviving: return "In Revival"
        }
    }

    private var lifecycleSubtitle: String {
        switch lifecycleState {
        case .dormant:
            if let lastFeed = feedLogs.first {
                let days = Int(Date().timeIntervalSince(lastFeed.timestamp) / 86400)
                return "Last fed \(days) day\(days == 1 ? "" : "s") ago"
            }
            return "No feeds logged yet"
        case .activating:
            if let risingFeed = feedLogs
                .first(where: { $0.starterFeedIntent == .activation && $0.peakTimestamp == nil })
            {
                let hours = Int(Date().timeIntervalSince(risingFeed.timestamp) / 3600)
                return "Rising on the counter — \(hours)h since feed"
            }
            return "Feed your starter on the counter to wake it up"
        case .active:
            let hours = Int(Date().timeIntervalSince(profile?.stateChangedAt ?? Date()) / 3600)
            return "Active for \(hours)h — build your levain or feed & refrigerate"
        case .reviving:
            return "Your starter is rebuilding strength. Follow the revival plan below."
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

    @ViewBuilder
    private var bakeAwarenessSection: some View {
        if lifecycleState == .dormant, let bakeStart = upcomingBakeStart {
            Section {
                HStack(spacing: 12) {
                    Image(systemName: "calendar.badge.clock")
                        .foregroundStyle(.orange)
                        .font(.title3)
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
                Button {
                    if let profile {
                        viewModel.activate(profile: profile)
                    }
                } label: {
                    Label("Activate Now", systemImage: "flame")
                }
                .tint(.orange)
            }
        }
    }

    @ViewBuilder
    private var suggestionSection: some View {
        if activeRevivalPlan == nil, let suggestion = currentSuggestion {
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
            } footer: {
                if suggestion.urgency == .urgent {
                    Text("This is getting urgent — don't wait too long.")
                        .font(.caption)
                        .foregroundStyle(.orange)
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

/// A live-feeling summary of an active revival plan.
///
/// Animates the symbol so the row reads as actively working, surfaces the
/// current step index, and picks a status subtitle appropriate to the
/// current step's state (pending future / ready to mix / rising / done).
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

// MARK: - Log Feed Sheet

struct LogFeedSheet: View {
    @Bindable var viewModel: StarterViewModel
    let modelContext: ModelContext
    var profile: StarterProfile?

    @Environment(\.dismiss) private var dismiss

    @State private var showRatioCustomisation = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Date & Time") {
                    DatePicker("Fed at", selection: $viewModel.feedTimestamp, in: ...Date())
                }

                Section {
                    HStack {
                        Text("Keep")
                        Spacer()
                        TextField("10", text: $viewModel.logFeedStarterGrams)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 80)
                        Text("g")
                            .foregroundStyle(.secondary)
                    }

                    if let grams = starterGrams {
                        let flourGrams = grams * Double(viewModel.feedRatioFlour) / Double(viewModel.feedRatioStarter)
                        let waterGrams = grams * Double(viewModel.feedRatioWater) / Double(viewModel.feedRatioStarter)
                        HStack {
                            Text("Flour")
                            Spacer()
                            Text("\(gramString(flourGrams)) g")
                                .foregroundStyle(.secondary)
                        }
                        HStack {
                            Text("Water")
                            Spacer()
                            Text("\(gramString(waterGrams)) g")
                                .foregroundStyle(.secondary)
                        }
                        HStack {
                            Text("Total")
                                .fontWeight(.medium)
                            Spacer()
                            Text("\(gramString(grams + flourGrams + waterGrams)) g")
                                .fontWeight(.medium)
                                .foregroundStyle(.secondary)
                        }
                    }

                    HStack {
                        Text("Ratio")
                        Spacer()
                        Text("\(viewModel.feedRatioStarter):\(viewModel.feedRatioFlour):\(viewModel.feedRatioWater)")
                            .foregroundStyle(.secondary)
                        Button {
                            showRatioCustomisation.toggle()
                        } label: {
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .rotationEffect(.degrees(showRatioCustomisation ? 90 : 0))
                        }
                        .buttonStyle(.plain)
                    }

                    if showRatioCustomisation {
                        Stepper("Starter: \(viewModel.feedRatioStarter)", value: $viewModel.feedRatioStarter, in: 1 ... 10)
                        Stepper("Flour: \(viewModel.feedRatioFlour)", value: $viewModel.feedRatioFlour, in: 1 ... 20)
                        Stepper("Water: \(viewModel.feedRatioWater)", value: $viewModel.feedRatioWater, in: 1 ... 20)
                    }
                } header: {
                    Text("Amount")
                } footer: {
                    Text(ratioGuidance)
                }

                Section("Details") {
                    HStack {
                        Text("Flour")
                        Spacer()
                        TextField("e.g. white, 50/50 white/rye", text: $viewModel.feedFlourType)
                            .multilineTextAlignment(.trailing)
                            .foregroundStyle(.secondary)
                    }

                    if isActivationFeed {
                        HStack {
                            Text("Kitchen temp")
                            Spacer()
                            Text("\(Int(viewModel.feedKitchenTemp))°C")
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $viewModel.feedKitchenTemp, in: 16 ... 32, step: 1)
                    }
                }

                howToFeedSection
            }
            .navigationTitle("Log Feed")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        viewModel.logFeed(modelContext: modelContext, profile: profile)
                    }
                }
            }
            .onAppear {
                if isActivationFeed {
                    viewModel.feedRatioFlour = 5
                    viewModel.feedRatioWater = 5
                } else {
                    viewModel.feedRatioFlour = 1
                    viewModel.feedRatioWater = 1
                }
                if viewModel.logFeedStarterGrams.isEmpty {
                    viewModel.logFeedStarterGrams = "10"
                }
            }
        }
    }

    private var isActivationFeed: Bool {
        profile?.starterLifecycleState == .activating
    }

    private var ratioGuidance: String {
        if isActivationFeed {
            return "1:5:5 gives a strong, predictable rise over ~5–6 hours. Use 1:3:3 for a faster peak (~3–4h), or 1:10:10 to time an overnight feed."
        }
        return "1:1:1 is enough food for 1–2 weeks in the fridge with minimal waste. Use 1:2:2 if storing for longer."
    }

    @ViewBuilder
    private var howToFeedSection: some View {
        let retain = starterGrams ?? 10
        let flour = retain * Double(viewModel.feedRatioFlour) / Double(viewModel.feedRatioStarter)
        let water = retain * Double(viewModel.feedRatioWater) / Double(viewModel.feedRatioStarter)

        let feedKind: FeedStepKind = profile?.starterLifecycleState == .activating ? .activation : .maintenance

        let instruction = FeedInstructions.instruction(
            for: FeedInstructionInput(
                retainGrams: retain,
                addFlourGrams: flour,
                addWaterGrams: water,
                flourType: viewModel.feedFlourType,
                kitchenTempC: viewModel.feedKitchenTemp,
                expectedPeakMinutes: 300,
                kind: feedKind,
                hadHooch: false,
                neglect: nil
            )
        )

        Section {
            ForEach(Array(instruction.steps.enumerated()), id: \.offset) { idx, line in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(idx + 1).")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Text(line)
                        .font(.caption)
                }
            }
        } header: {
            Text("How to feed")
        }
    }

    private var starterGrams: Double? {
        let trimmed = viewModel.logFeedStarterGrams.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let v = Double(trimmed), v > 0 else { return nil }
        return v
    }

    private func gramString(_ grams: Double) -> String {
        let rounded = grams.rounded()
        if abs(rounded - grams) < 0.05 {
            return "\(Int(rounded))"
        }
        return String(format: "%.1f", grams)
    }
}

// MARK: - Edit Feed Log Sheet

struct EditFeedLogSheet: View {
    @Bindable var log: StarterFeedLog
    let profile: StarterProfile?
    let allLogs: [StarterFeedLog]
    @Bindable var viewModel: StarterViewModel

    @Environment(\.dismiss) private var dismiss

    @State private var timestamp: Date
    @State private var ratioStarter: Int
    @State private var ratioFlour: Int
    @State private var ratioWater: Int
    @State private var flourType: String
    @State private var kitchenTemp: Double
    @State private var starterGrams: String

    init(log: StarterFeedLog, profile: StarterProfile?, allLogs: [StarterFeedLog], viewModel: StarterViewModel) {
        self.log = log
        self.profile = profile
        self.allLogs = allLogs
        self.viewModel = viewModel
        _timestamp = State(initialValue: log.timestamp)
        _ratioStarter = State(initialValue: log.ratioStarter)
        _ratioFlour = State(initialValue: log.ratioFlour)
        _ratioWater = State(initialValue: log.ratioWater)
        _flourType = State(initialValue: log.flourType)
        _kitchenTemp = State(initialValue: log.kitchenTemperatureCelsius)
        _starterGrams = State(initialValue: log.starterGrams.map { String(Int($0)) } ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Date & Time") {
                    DatePicker("Fed at", selection: $timestamp, in: ...Date())
                }

                Section("Ratio") {
                    Stepper("Starter: \(ratioStarter)", value: $ratioStarter, in: 1 ... 10)
                    Stepper("Flour: \(ratioFlour)", value: $ratioFlour, in: 1 ... 20)
                    Stepper("Water: \(ratioWater)", value: $ratioWater, in: 1 ... 20)
                }

                Section {
                    HStack {
                        Text("Starter amount")
                        Spacer()
                        TextField("optional", text: $starterGrams)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 100)
                        Text("g")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Amount")
                }

                Section("Details") {
                    HStack {
                        Text("Flour")
                        Spacer()
                        TextField("e.g. white, 50/50 white/rye", text: $flourType)
                            .multilineTextAlignment(.trailing)
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("Kitchen temp")
                        Spacer()
                        Text("\(Int(kitchenTemp))°C")
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $kitchenTemp, in: 16 ... 32, step: 1)
                }

                if log.peakTimestamp != nil {
                    Section {
                        Button("Clear Peak Data", role: .destructive) {
                            log.peakTimestamp = nil
                            log.timeToPeakMinutes = nil
                        }
                    } footer: {
                        Text("Removes the recorded peak time so you can mark it again.")
                    }
                }
            }
            .navigationTitle("Edit Feed")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        applyChanges()
                        dismiss()
                    }
                }
            }
        }
    }

    private func applyChanges() {
        let timestampChanged = abs(log.timestamp.timeIntervalSince(timestamp)) > 60
        log.timestamp = timestamp
        log.ratioStarter = ratioStarter
        log.ratioFlour = ratioFlour
        log.ratioWater = ratioWater
        log.flourType = flourType
        log.kitchenTemperatureCelsius = kitchenTemp
        log.starterGrams = Double(starterGrams.trimmingCharacters(in: .whitespaces))

        if timestampChanged, let peak = log.peakTimestamp {
            log.timeToPeakMinutes = peak.timeIntervalSince(timestamp) / 60.0
        }

        viewModel.updateProfileAverages(profile: profile, feedLogs: allLogs)
    }
}

#Preview {
    StarterTab()
        .modelContainer(for: StarterFeedLog.self, inMemory: true)
}
