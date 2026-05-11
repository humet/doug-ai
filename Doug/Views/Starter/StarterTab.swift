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

    private var nextFeed: Date? {
        viewModel.nextFeedTime(
            profile: profile,
            feedLogs: feedLogs,
            availability: availabilities.first,
            windows: Array(windows),
            upcomingBakeStart: upcomingBakeStart
        )
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
                LogFeedSheet(viewModel: viewModel, modelContext: modelContext)
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
                        viewModel.deleteFeedLog(log, modelContext: modelContext, profile: profile, feedLogs: Array(feedLogs))
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
            .task(id: nextFeed) {
                await viewModel.syncFeedReminder(
                    nextFeed: nextFeed,
                    upcomingBakeStart: upcomingBakeStart
                )
            }
        }
    }

    // MARK: - Sections

    private var healthSection: some View {
        Section {
            HStack {
                if activeRevivalPlan != nil {
                    Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                        .foregroundStyle(.tint)
                        .font(.title2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("In Revival")
                            .font(.headline)
                        Text("Your starter is rebuilding strength. Follow the revival plan below.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    let status = viewModel.healthStatus(profile: profile, feedLogs: feedLogs)
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
    private var nextFeedSection: some View {
        if activeRevivalPlan == nil, let nextFeed {
            Section {
                HStack {
                    Label("Next feed", systemImage: "clock")
                    Spacer()
                    RelativeTimeLabel(date: nextFeed)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Spacer()
                    Text(nextFeed, format: .dateTime.weekday(.wide).hour().minute())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } footer: {
                Text(viewModel.feedContext(nextFeed: nextFeed, upcomingBakeStart: upcomingBakeStart))
                    .font(.caption)
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

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Date & Time") {
                    DatePicker("Fed at", selection: $viewModel.feedTimestamp, in: ...Date())
                }

                howToFeedSection

                Section("Ratio") {
                    Stepper("Starter: \(viewModel.feedRatioStarter)", value: $viewModel.feedRatioStarter, in: 1 ... 10)
                    Stepper("Flour: \(viewModel.feedRatioFlour)", value: $viewModel.feedRatioFlour, in: 1 ... 20)
                    Stepper("Water: \(viewModel.feedRatioWater)", value: $viewModel.feedRatioWater, in: 1 ... 20)
                }

                Section {
                    HStack {
                        Text("Starter amount")
                        Spacer()
                        TextField("optional", text: $viewModel.logFeedStarterGrams)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 100)
                        Text("g")
                            .foregroundStyle(.secondary)
                    }

                    if let grams = starterGrams {
                        HStack {
                            Text("Flour")
                            Spacer()
                            Text(
                                "\(gramString(grams * Double(viewModel.feedRatioFlour) / Double(viewModel.feedRatioStarter))) g"
                            )
                            .foregroundStyle(.secondary)
                        }
                        HStack {
                            Text("Water")
                            Spacer()
                            Text(
                                "\(gramString(grams * Double(viewModel.feedRatioWater) / Double(viewModel.feedRatioStarter))) g"
                            )
                            .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Amount")
                } footer: {
                    Text("Enter how many grams of starter you're keeping. We'll calculate flour and water for you.")
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
                    Slider(value: $viewModel.feedKitchenTemp, in: 16 ... 32, step: 1)
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

    @ViewBuilder
    private var howToFeedSection: some View {
        let retain = starterGrams ?? 20
        let flour = retain * Double(viewModel.feedRatioFlour) / Double(viewModel.feedRatioStarter)
        let water = retain * Double(viewModel.feedRatioWater) / Double(viewModel.feedRatioStarter)

        let instruction = FeedInstructions.instruction(
            for: FeedInstructionInput(
                retainGrams: retain,
                addFlourGrams: flour,
                addWaterGrams: water,
                flourType: viewModel.feedFlourType,
                kitchenTempC: viewModel.feedKitchenTemp,
                expectedPeakMinutes: 300,
                kind: .maintenance,
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
                    Picker("Flour type", selection: $flourType) {
                        Text("White").tag("white")
                        Text("Whole Wheat").tag("whole wheat")
                        Text("Rye").tag("rye")
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
