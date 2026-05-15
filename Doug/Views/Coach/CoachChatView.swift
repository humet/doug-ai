import SwiftData
import SwiftUI

struct CoachChatView: View {
    @State private var viewModel = CoachViewModel()
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @FocusState private var inputFocused: Bool

    let schedule: Schedule?
    let scheduleViewModel: ScheduleViewModel?
    var initialMessage: String?
    var starterProfile: StarterProfile?
    var feedLogs: [StarterFeedLog] = []
    var unavailableWindows: [UnavailableWindow] = []
    var revivalPlan: RevivalPlan?

    var body: some View {
        NavigationStack {
            messageList
                .safeAreaInset(edge: .bottom) {
                    inputBar
                }
                .scrollDismissesKeyboard(.interactively)
                .navigationTitle("Coach")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
                .task {
                    viewModel.loadHistory(
                        modelContext: modelContext,
                        schedule: schedule
                    )
                    if let initialMessage, !initialMessage.isEmpty {
                        viewModel.inputText = initialMessage
                        viewModel.send(
                            modelContext: modelContext,
                            schedule: schedule,
                            bakeContext: buildBakeContext(),
                            starterContext: buildStarterContext(),
                            availabilityContext: buildAvailabilityContext()
                        )
                    }
                }
                .onDisappear {
                    viewModel.cancelStream()
                }
        }
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 8) {
                    if viewModel.messages.isEmpty, !viewModel.isStreaming {
                        emptyState
                    }

                    ForEach(viewModel.messages) { message in
                        CoachMessageBubble(
                            role: message.messageRole,
                            content: message.content
                        )
                        .id(message.persistentModelID)

                        if message.actionsResolved, let actions = message.actions, !actions.isEmpty {
                            CoachActionCard(
                                actions: actions,
                                selections: message.actionsDismissed ? [] : Set(actions.map(\.id)),
                                resolved: true,
                                dismissed: message.actionsDismissed,
                                onToggle: { _ in },
                                onApply: {},
                                onDismiss: {}
                            )
                        }
                    }

                    if viewModel.isStreaming {
                        if viewModel.streamingText.isEmpty {
                            HStack {
                                ProgressView()
                                    .padding(.trailing, 4)
                                Text("Thinking...")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Spacer()
                            }
                            .padding(.horizontal)
                        } else {
                            CoachMessageBubble(role: .assistant, content: viewModel.streamingText)
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }

                    if !viewModel.isStreaming, !viewModel.pendingActions.isEmpty {
                        CoachActionCard(
                            actions: viewModel.pendingActions,
                            selections: viewModel.actionSelections,
                            resolved: false,
                            dismissed: false,
                            onToggle: { viewModel.toggleAction($0) },
                            onApply: {
                                if let scheduleViewModel {
                                    viewModel.applyActions(
                                        schedule: schedule,
                                        scheduleViewModel: scheduleViewModel,
                                        modelContext: modelContext
                                    )
                                }
                            },
                            onDismiss: { viewModel.dismissActions() }
                        )
                        .id("pending-actions")
                    }
                }
                .padding()
            }
            .defaultScrollAnchor(.bottom)
            .onChange(of: viewModel.messages.count) {
                withAnimation {
                    if viewModel.isStreaming {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    } else if let last = viewModel.messages.last {
                        proxy.scrollTo(last.persistentModelID, anchor: .bottom)
                    }
                }
            }
            .onChange(of: viewModel.streamingText) {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
    }

    private var inputBar: some View {
        VStack(spacing: 0) {
            Divider()

            if let error = viewModel.error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
                    .padding(.top, 6)
            }

            HStack(spacing: 8) {
                TextField("Ask about your bake...", text: $viewModel.inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1 ... 4)
                    .padding(10)
                    .background(DougTheme.warmParchment, in: .rect(cornerRadius: 12))
                    .focused($inputFocused)

                Button {
                    viewModel.send(
                        modelContext: modelContext,
                        schedule: schedule,
                        bakeContext: buildBakeContext(),
                        starterContext: buildStarterContext(),
                        availabilityContext: buildAvailabilityContext()
                    )
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(
                            viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel
                                .isStreaming
                                ? .secondary
                                : DougTheme.sourdoughBrown
                        )
                }
                .disabled(
                    viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isStreaming
                )
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(.ultraThinMaterial)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "bubble.left.and.text.bubble.right")
                .font(.largeTitle)
                .foregroundStyle(DougTheme.crustGold)
            Text("Your baking coach")
                .font(.headline)
            Text("Ask about your current bake, timing, temperatures, or sourdough technique.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 60)
        .padding(.horizontal, 32)
    }

    private func buildBakeContext() -> BakeContextPayload? {
        guard let schedule else { return nil }
        let steps = schedule.steps
            .filter { $0.parentStep == nil }
            .sorted { $0.sequenceIndex < $1.sequenceIndex }

        let recipe = schedule.recipe
        return BakeContextPayload(
            recipeId: schedule.recipeID,
            recipeName: recipe.name,
            hydrationPercent: recipe.hydrationPercent,
            kitchenTempCelsius: schedule.kitchenTemperatureCelsius,
            targetBreadReadyTime: schedule.targetBreadReadyTime,
            recipeMethod: recipe.method.map { methodStep in
                let st = methodStep.stepType
                return BakeContextPayload.RecipeMethodPayload(
                    stepTypeId: methodStep.stepTypeID.rawValue,
                    label: st.label,
                    classification: st.classification.rawValue,
                    baseDurationMinutes: methodStep.effectiveDuration,
                    flexRangeMin: methodStep.effectiveFlexRange?.lowerBound,
                    flexRangeMax: methodStep.effectiveFlexRange?.upperBound
                )
            },
            recipeIngredients: BakeContextPayload.IngredientsPayload(
                flourGrams: recipe.ingredients.flourGrams,
                waterGrams: recipe.ingredients.waterGrams,
                saltGrams: recipe.ingredients.saltGrams,
                levainGrams: recipe.ingredients.levainGrams,
                extras: recipe.ingredients.extras.map { ($0.name, $0.grams) }
            ),
            steps: steps.map { step in
                let stepType = step.stepType
                return BakeContextPayload.StepPayload(
                    stepTypeId: step.stepTypeID,
                    label: stepType.label,
                    classification: stepType.classification.rawValue,
                    status: step.status,
                    computedStartTime: step.computedStartTime,
                    computedEndTime: step.computedEndTime,
                    durationMinutes: step.computedDurationMinutes,
                    flexRangeMin: stepType.flexRange?.lowerBound,
                    flexRangeMax: stepType.flexRange?.upperBound
                )
            },
            temperatureReadings: schedule.temperatureReadings.map { reading in
                BakeContextPayload.TempReadingPayload(
                    timestamp: reading.timestamp,
                    temperatureCelsius: reading.temperatureCelsius,
                    accumulatedDegreeHours: reading.accumulatedDegreeHours,
                    associatedStepTypeId: reading.associatedStepTypeID
                )
            },
            degreeHourTarget: schedule.recipe.degreeHourTarget,
            delays: computeDelays(for: schedule)
        )
    }

    private func computeDelays(for schedule: Schedule) -> [BakeContextPayload.DelayPayload] {
        schedule.steps
            .filter { $0.parentStep == nil }
            .sorted { $0.sequenceIndex < $1.sequenceIndex }
            .compactMap { step in
                guard step.stepStatus == .active || step.stepStatus == .done,
                      let actualEnd = step.actualEndTime
                else { return nil }
                let delay = actualEnd.timeIntervalSince(step.computedEndTime) / 60.0
                guard delay > 1 else { return nil }
                return BakeContextPayload.DelayPayload(
                    stepLabel: step.stepType.label,
                    delayMinutes: delay
                )
            }
    }

    private func buildStarterContext() -> StarterContextPayload? {
        guard let profile = starterProfile else { return nil }
        let lastFeed = feedLogs.first
        let daysSinceLastFeed: Double? = lastFeed.map {
            Date().timeIntervalSince($0.timestamp) / 86400
        }
        return StarterContextPayload(
            storageType: profile.storageType,
            lifecycleState: profile.lifecycleState,
            maintenanceCycleDays: profile.maintenanceCycleDays,
            healthStatus: profile.healthStatus,
            daysSinceLastFeed: daysSinceLastFeed,
            recentFeeds: Array(feedLogs.prefix(5)).map { log in
                StarterContextPayload.FeedPayload(
                    timestamp: log.timestamp,
                    ratio: log.ratioDescription,
                    flourType: log.flourType,
                    kitchenTempCelsius: log.kitchenTemperatureCelsius,
                    timeToPeakMinutes: log.timeToPeakMinutes,
                    intent: log.feedIntent,
                    starterGrams: log.starterGrams,
                    flourGrams: log.flourGrams,
                    waterGrams: log.waterGrams
                )
            },
            revivalPlan: revivalPlan.map { plan in
                let steps = plan.feedSteps.sorted { $0.sequenceIndex < $1.sequenceIndex }
                let peakTrend = steps.compactMap(\.timeToPeakMinutes)
                return StarterContextPayload.RevivalPayload(
                    isActive: plan.revivalStatus == .active,
                    currentStep: plan.currentStepIndex + 1,
                    totalSteps: steps.count,
                    peakTimeTrend: peakTrend
                )
            }
        )
    }

    private func buildAvailabilityContext() -> AvailabilityContextPayload? {
        let active = unavailableWindows.filter(\.isActive)
        guard !active.isEmpty else { return nil }
        let cal = Calendar.current
        let referenceDate = schedule?.targetBreadReadyTime ?? Date()
        return AvailabilityContextPayload(
            unavailableWindows: active.compactMap { w in
                guard let start = cal.date(
                    bySettingHour: w.startHour, minute: w.startMinute, second: 0, of: referenceDate
                ),
                    let end = cal.date(
                        bySettingHour: w.endHour, minute: w.endMinute, second: 0, of: referenceDate
                    )
                else { return nil }
                return AvailabilityContextPayload.WindowPayload(
                    start: start,
                    end: end,
                    label: w.name
                )
            }
        )
    }
}
