import SwiftData
import SwiftUI

struct ScheduleTab: View {
    @State private var viewModel = ScheduleViewModel()
    @State private var showConfig = false
    @State private var detailStep: ScheduleStep?
    @State private var showCancelConfirm = false

    @Query private var availabilities: [UserAvailability]
    @Query private var windows: [UnavailableWindow]
    @Query private var profiles: [StarterProfile]
    @Query(sort: \StarterFeedLog.timestamp, order: .reverse)
    private var feedLogs: [StarterFeedLog]

    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Schedule")
                .navigationDestination(for: RecipeID.self) { recipeID in
                    let recipe = RecipeBook.recipe(for: recipeID)
                    RecipeDetailView(
                        recipe: recipe,
                        showPlanCTA: true,
                        onPlanBake: { planBake(for: recipeID) }
                    )
                }
                .toolbar {
                    if viewModel.activeSchedule != nil {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                viewModel.showRecipeDetailSheet = true
                            } label: {
                                Image(systemName: "book.pages")
                            }
                            .accessibilityLabel("Recipe")
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                            bakeActionsMenu
                        }
                    }
                }
                .sheet(isPresented: $showConfig) {
                    ScheduleConfigSheet(viewModel: viewModel) {
                        let canBake = viewModel.preBakeHealthCheck(
                            profile: profiles.first,
                            feedLogs: feedLogs
                        )
                        if canBake {
                            withAnimation(.smooth) {
                                viewModel.startBake(modelContext: modelContext)
                            }
                            showConfig = false
                        }
                    }
                }
                .sheet(isPresented: $viewModel.showConflictSheet) {
                    if let conflict = viewModel.conflict {
                        ConflictResolutionSheet(
                            conflict: conflict,
                            recipe: viewModel.selectedRecipe,
                            kitchenTemp: viewModel.kitchenTemperature
                        ) { option in
                            viewModel.apply(
                                option: option,
                                availability: availabilities.first,
                                windows: Array(windows),
                                feedLogs: Array(feedLogs)
                            )
                        }
                    }
                }
                .sheet(isPresented: $viewModel.showColdRetardSlider) {
                    if let step = viewModel.coldRetardStep,
                       let range = viewModel.coldRetardFlexRange
                    {
                        ColdRetardSliderView(
                            coldRetardStep: step,
                            flexRange: range
                        ) { newDuration in
                            viewModel.adjustColdRetard(to: newDuration, modelContext: modelContext)
                        }
                    }
                }
                .sheet(isPresented: $viewModel.showTemperatureEntry) {
                    if let schedule = viewModel.activeSchedule {
                        TemperatureEntryView(
                            schedule: schedule,
                            foldStep: viewModel.selectedFoldStep
                        )
                    }
                }
                .sheet(item: $viewModel.pendingFoldEntry) { entry in
                    if let schedule = viewModel.activeSchedule {
                        TemperatureEntryView(
                            schedule: schedule,
                            foldStep: schedule.steps.first {
                                $0.stepTypeID == entry.stepTypeID
                                    && $0.sequenceIndex == entry.sequenceIndex
                            }
                        )
                    }
                }
                .sheet(item: $detailStep) { step in
                    StepDetailSheet(
                        step: step,
                        viewModel: viewModel,
                        isMostRecentlyCompleted: isMostRecentlyCompleted(step)
                    )
                }
                .sheet(isPresented: $viewModel.showRecipeDetailSheet) {
                    if let schedule = viewModel.activeSchedule {
                        NavigationStack {
                            RecipeDetailView(
                                recipe: schedule.recipe,
                                showPlanCTA: false,
                                onPlanBake: nil
                            )
                            .toolbar {
                                ToolbarItem(placement: .confirmationAction) {
                                    Button("Done") {
                                        viewModel.showRecipeDetailSheet = false
                                    }
                                }
                            }
                        }
                    }
                }
                .alert(
                    "Cancel this bake?",
                    isPresented: $showCancelConfirm
                ) {
                    Button("Keep baking", role: .cancel) {}
                    Button("Cancel bake", role: .destructive) {
                        withAnimation(.smooth) {
                            viewModel.cancelBake(modelContext: modelContext)
                        }
                    }
                } message: {
                    Text("Your active schedule will be ended and all pending notifications cleared.")
                }
                .alert(
                    "Starter Not Ready",
                    isPresented: Binding(
                        get: { viewModel.starterHealthBlock != nil },
                        set: { if !$0 { viewModel.starterHealthBlock = nil } }
                    )
                ) {
                    Button("OK") { viewModel.starterHealthBlock = nil }
                } message: {
                    if viewModel.starterHealthBlock == .needsRevival {
                        Text("Your starter needs revival before baking. Check the Starter tab for a revival plan.")
                    } else {
                        Text(
                            "Your starter needs a feed before baking. Feed it and wait for it to peak, then try again."
                        )
                    }
                }
                .task {
                    viewModel.restoreActiveSchedule(modelContext: modelContext)
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        viewModel.restoreActiveSchedule(modelContext: modelContext)
                        viewModel.advanceIfReady(now: Date(), modelContext: modelContext)
                    }
                }
                .onChange(of: viewModel.pendingStepDetail) { _, newValue in
                    guard let detail = newValue,
                          let schedule = viewModel.activeSchedule,
                          let step = schedule.steps.first(where: {
                              $0.stepTypeID == detail.stepTypeID
                                  && $0.sequenceIndex == detail.sequenceIndex
                          }) else { return }
                    detailStep = step
                    viewModel.pendingStepDetail = nil
                }
        }
    }

    // MARK: - Main content

    @ViewBuilder
    private var content: some View {
        if let schedule = viewModel.activeSchedule {
            activeBake(schedule: schedule)
        } else {
            recipePicker
        }
    }

    // MARK: - Recipe picker (no active bake)

    private var recipePicker: some View {
        ScrollView {
            VStack(spacing: 16) {
                ForEach(RecipeBook.all) { recipe in
                    NavigationLink(value: recipe.id) {
                        RecipeCard(recipe: recipe)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
        .background(DougTheme.warmCream)
    }

    // MARK: - Active bake

    private func activeBake(schedule: Schedule) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let now = context.date
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    activeHeader(schedule: schedule)

                    if let pausedAt = schedule.pausedAt {
                        PausedBanner(
                            pausedAt: pausedAt,
                            viewModel: viewModel,
                            referenceDate: now
                        )
                    }

                    if !viewModel.activeConflicts.isEmpty {
                        ConflictBanner(conflicts: viewModel.activeConflicts)
                    }

                    CompletedStepsDisclosure(
                        completedSteps: completedSteps(in: schedule),
                        referenceDate: now,
                        onSelect: { detailStep = $0 }
                    )

                    if let focus = focusStep(in: schedule) {
                        NowStepHero(
                            step: focus,
                            viewModel: viewModel,
                            referenceDate: now,
                            onOpenDetail: { detailStep = $0 }
                        )
                    }

                    DegreeHoursChartView(
                        readings: schedule.temperatureReadings,
                        targetDegreeHours: schedule.recipe.degreeHourTarget
                    )

                    if let _ = viewModel.coldRetardStep {
                        Button {
                            viewModel.showColdRetardSlider = true
                        } label: {
                            Label("Adjust Cold Retard", systemImage: "clock.arrow.2.circlepath")
                                .font(.subheadline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                        }
                        .adaptiveGlassButtonStyle()
                    }

                    upcomingSteps(in: schedule, now: now)
                }
                .padding()
            }
            .background(DougTheme.warmCream)
            .task(id: effectiveTickBucket(now: now)) {
                viewModel.advanceIfReady(now: now, modelContext: modelContext)
            }
        }
    }

    @ViewBuilder
    private func activeHeader(schedule: Schedule) -> some View {
        let header = HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(schedule.recipe.name)
                    .font(.title2.bold())
                Text("Bread ready \(schedule.targetBreadReadyTime, style: .relative)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("Active")
                .font(.caption.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(.green, in: .capsule)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)

        if reduceTransparency {
            header.background(.ultraThinMaterial, in: .rect(cornerRadius: 16))
        } else {
            header.glassEffect(.regular, in: .rect(cornerRadius: 16))
        }
    }

    private func upcomingSteps(in schedule: Schedule, now: Date) -> some View {
        let all = orderedTopLevelSteps(in: schedule)
        let upcomingAndActive = all.filter { $0.stepStatus != .done && $0.stepStatus != .skipped }
        let focus = focusStep(in: schedule)
        let rest = upcomingAndActive.filter { $0 !== focus }

        return VStack(alignment: .leading, spacing: 10) {
            if !rest.isEmpty {
                Text("Coming up")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
            ForEach(rest) { step in
                CompactStepRow(
                    step: step,
                    referenceDate: now,
                    isSubStep: false,
                    onTap: { detailStep = step }
                )

                ForEach(step.subSteps.sorted { $0.sequenceIndex < $1.sequenceIndex }) { sub in
                    CompactStepRow(
                        step: sub,
                        referenceDate: now,
                        isSubStep: true,
                        onTap: { detailStep = sub }
                    )
                }
            }
        }
    }

    // MARK: - Bake actions menu

    private var bakeActionsMenu: some View {
        Menu {
            if let schedule = viewModel.activeSchedule, canFinishBake(in: schedule) {
                Button {
                    withAnimation(.smooth) {
                        viewModel.finishBake(modelContext: modelContext)
                    }
                } label: {
                    Label("Finish bake", systemImage: "checkmark.seal")
                }
            }
            Button(role: .destructive) {
                showCancelConfirm = true
            } label: {
                Label("Cancel bake", systemImage: "xmark.circle")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .accessibilityLabel("Bake actions")
    }

    // MARK: - Derived helpers

    private func orderedTopLevelSteps(in schedule: Schedule) -> [ScheduleStep] {
        schedule.steps
            .filter { $0.parentStep == nil }
            .sorted { $0.sequenceIndex < $1.sequenceIndex }
    }

    private func completedSteps(in schedule: Schedule) -> [ScheduleStep] {
        orderedTopLevelSteps(in: schedule).filter {
            $0.stepStatus == .done || $0.stepStatus == .skipped
        }
    }

    private func focusStep(in schedule: Schedule) -> ScheduleStep? {
        let steps = orderedTopLevelSteps(in: schedule)
        if let active = steps.first(where: { $0.stepStatus == .active }) { return active }
        return steps.first { $0.stepStatus == .upcoming }
    }

    private func canFinishBake(in schedule: Schedule) -> Bool {
        let steps = orderedTopLevelSteps(in: schedule)
        guard let last = steps.last else { return false }
        return last.stepStatus == .done
    }

    private func isMostRecentlyCompleted(_ step: ScheduleStep) -> Bool {
        guard let schedule = viewModel.activeSchedule else { return false }
        let completed = completedSteps(in: schedule)
            .sorted { $0.sequenceIndex > $1.sequenceIndex }
        return completed.first?.sequenceIndex == step.sequenceIndex
    }

    /// Bucket the tick date so `.task(id:)` only re-runs once per second — driving
    /// `advanceIfReady` without thrashing.
    private func effectiveTickBucket(now: Date) -> Int {
        Int(now.timeIntervalSince1970)
    }

    private func planBake(for recipeID: RecipeID) {
        viewModel.selectedRecipeID = recipeID
        viewModel.buildPreview(
            availability: availabilities.first,
            windows: Array(windows),
            feedLogs: Array(feedLogs)
        )
        if viewModel.conflict == nil {
            showConfig = true
        }
    }
}

// MARK: - Recipe Card (plain, for navigation)

private struct RecipeCard: View {
    let recipe: Recipe

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(recipe.name)
                    .font(.headline)
                Spacer()
                Text("\(recipe.hydrationPercent)%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(recipe.description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            HStack {
                Label(recipe.difficulty.rawValue.capitalized, systemImage: "chart.bar")
                Spacer()
                Label(
                    "\(recipe.approximateTotalHours.lowerBound)–\(recipe.approximateTotalHours.upperBound)h",
                    systemImage: "clock"
                )
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground), in: .rect(cornerRadius: 16))
    }
}

#Preview {
    ScheduleTab()
        .modelContainer(for: Schedule.self, inMemory: true)
}
