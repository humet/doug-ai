import SwiftData
import SwiftUI

struct ScheduleTab: View {
    @State private var viewModel = ScheduleViewModel()
    @State private var showConfig = false
    @State private var detailStep: ScheduleStep?
    @State private var showCancelConfirm = false
    @State private var showCoachChat = false
    @State private var coachPrefill: String?

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
                                showCoachChat = true
                            } label: {
                                Image(systemName: "bubble.left.and.text.bubble.right")
                            }
                            .accessibilityLabel("Coach")
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                viewModel.showRecipeDetailSheet = true
                            } label: {
                                Image(systemName: "list.bullet.rectangle")
                            }
                            .accessibilityLabel("Recipe")
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                            bakeActionsMenu
                        }
                    }
                }
                .sheet(isPresented: $showConfig, onDismiss: { viewModel.resetOverrides() }) {
                    ScheduleConfigSheet(viewModel: viewModel) {
                        if viewModel.hasActivationPreamble || viewModel.detectedLevain != nil {
                            withAnimation(.smooth) {
                                viewModel.startBake(modelContext: modelContext)
                            }
                            showConfig = false
                            return
                        }
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
                .sheet(isPresented: $viewModel.showFlexStepSlider) {
                    if let step = viewModel.flexibleStep,
                       let range = viewModel.flexibleStepFlexRange
                    {
                        let recipe = viewModel.activeSchedule.map {
                            RecipeBook.recipe(for: RecipeID(rawValue: $0.recipeID)!)
                        }
                        FlexStepSliderView(
                            step: step,
                            flexRange: range,
                            remainingMinutesAfterStep: viewModel.remainingMinutesAfterFlexStep,
                            completionLabel: recipe?.completionLabel ?? "Bread Ready"
                        ) { newDuration in
                            viewModel.adjustFlexibleStep(to: newDuration, modelContext: modelContext)
                        }
                    }
                }
                .sheet(isPresented: $viewModel.showTemperatureEntry) {
                    if let schedule = viewModel.activeSchedule {
                        TemperatureEntryView(
                            schedule: schedule,
                            foldStep: viewModel.selectedFoldStep,
                            onSave: { viewModel.handleNewTemperatureReading(schedule: schedule) }
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
                            },
                            onSave: { viewModel.handleNewTemperatureReading(schedule: schedule) }
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
                .sheet(isPresented: $showCoachChat) {
                    CoachChatView(
                        schedule: viewModel.activeSchedule,
                        scheduleViewModel: viewModel,
                        initialMessage: coachPrefill
                    )
                    .onDisappear { coachPrefill = nil }
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
                            "Your starter is in the fridge. Activate it on the counter and wait for it to peak, then try again."
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
                    .buttonStyle(RecipeCardButtonStyle())
                }
            }
            .padding()
        }
    }

    // MARK: - Active bake

    private func activeBake(schedule: Schedule) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let now = context.date
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    activeHeader(schedule: schedule)
                    IngredientsDisclosure(ingredients: schedule.recipe.ingredients)

                    if let pausedAt = schedule.pausedAt {
                        PausedBanner(
                            pausedAt: pausedAt,
                            viewModel: viewModel,
                            referenceDate: now
                        )
                    }

                    if !viewModel.activeConflicts.isEmpty {
                        ConflictBanner(conflicts: viewModel.activeConflicts) { prefill in
                            coachPrefill = prefill
                            showCoachChat = true
                        }
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
                            onOpenDetail: { detailStep = $0 },
                            onOpenCoach: { prefill in
                                coachPrefill = prefill
                                showCoachChat = true
                            },
                            starterProfile: profiles.first
                        )
                    }

                    if let adjustment = viewModel.lastScheduleAdjustment {
                        ScheduleAdjustmentBanner(adjustment: adjustment) {
                            viewModel.lastScheduleAdjustment = nil
                        }
                    }

                    if !schedule.temperatureReadings.isEmpty {
                        DegreeHoursChartView(
                            readings: schedule.temperatureReadings,
                            targetDegreeHours: schedule.recipe.degreeHourTarget
                        )

                        if isBulkFermentActive(in: schedule) {
                            Button {
                                viewModel.selectedFoldStep = nil
                                viewModel.showTemperatureEntry = true
                            } label: {
                                Label("Add Temperature Reading", systemImage: "thermometer.medium")
                                    .font(.caption.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                            }
                            .adaptiveGlassButtonStyle()
                        }
                    }

                    if let flexStep = viewModel.flexibleStep,
                       let stepID = StepTypeID(rawValue: flexStep.stepTypeID)
                    {
                        Button {
                            viewModel.showFlexStepSlider = true
                        } label: {
                            Label("Adjust \(StepTypeRegistry.type(for: stepID).label)", systemImage: "clock.arrow.2.circlepath")
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

        let conflictIndices = Set(viewModel.activeConflicts.map(\.stepSequenceIndex))

        return VStack(alignment: .leading, spacing: 10) {
            if !rest.isEmpty {
                Text("Coming up")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
            let restArray = Array(rest)
            ForEach(Array(restArray.enumerated()), id: \.element.id) { index, step in
                if index > 0, !Calendar.current.isDate(restArray[index - 1].computedStartTime, inSameDayAs: step.computedStartTime) {
                    OvernightDivider(from: restArray[index - 1].computedStartTime, to: step.computedStartTime)
                }

                CompactStepRow(
                    step: step,
                    referenceDate: now,
                    isSubStep: false,
                    hasConflict: conflictIndices.contains(step.sequenceIndex),
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

    private func isBulkFermentActive(in schedule: Schedule) -> Bool {
        orderedTopLevelSteps(in: schedule).contains {
            StepTypeID(rawValue: $0.stepTypeID) == .bulkFerment && $0.stepStatus == .active
        }
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

        let profile = profiles.first
        let state = profile?.starterLifecycleState ?? .dormant
        let duration = EarliestBakeEstimator.recipeDurationMinutes(
            recipe: viewModel.selectedRecipe,
            kitchenTempC: viewModel.kitchenTemperature
        )
        let activationLogs = feedLogs.filter { $0.starterFeedIntent == .activation }
        let lastActivation = activationLogs.first.map { FeedLogInput(from: $0) }
        let estimate = EarliestBakeEstimator.estimate(
            lifecycleState: state,
            stateChangedAt: profile?.stateChangedAt ?? Date(),
            lastActivationFeed: lastActivation,
            activePeakAverage: profile?.activePeakAverageMinutes,
            kitchenTempC: viewModel.kitchenTemperature,
            scheduleDurationMinutes: duration,
            storageType: profile?.starterStorageType ?? .fridge
        )
        let earliest = estimate.earliestBreadReady
        let calendar = Calendar.current
        let snapped = calendar.date(bySetting: .minute, value: 0, of: earliest)
            .flatMap { calendar.date(byAdding: .hour, value: 1, to: $0) }
            ?? earliest
        viewModel.targetDate = snapped

        viewModel.buildPreview(
            availability: availabilities.first,
            windows: Array(windows),
            feedLogs: Array(feedLogs),
            starterProfile: profiles.first
        )
        showConfig = true
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
        .background(DougTheme.warmParchment, in: .rect(cornerRadius: 16))
    }
}

private struct RecipeCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .animation(.smooth(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Ingredients Disclosure

private struct IngredientsDisclosure: View {
    let ingredients: Ingredients
    @State private var expanded = false

    var body: some View {
        VStack(spacing: 8) {
            Button {
                withAnimation(.smooth(duration: 0.25)) {
                    expanded.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "scalemass")
                        .foregroundStyle(.secondary)
                    Text("Ingredients")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(DougTheme.cardBackground, in: .rect(cornerRadius: 12))
            }
            .buttonStyle(.plain)

            if expanded {
                IngredientsTableView(ingredients: ingredients)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

#Preview {
    ScheduleTab()
        .modelContainer(for: Schedule.self, inMemory: true)
}
