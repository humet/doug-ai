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

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                messageList
                inputBar
            }
            .background(DougTheme.warmCream)
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
                        starterContext: nil,
                        availabilityContext: nil
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

                    if viewModel.isStreaming, !viewModel.streamingText.isEmpty {
                        CoachMessageBubble(role: .assistant, content: viewModel.streamingText)
                            .id("streaming")
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

                    if viewModel.isStreaming, viewModel.streamingText.isEmpty {
                        HStack {
                            ProgressView()
                                .padding(.trailing, 4)
                            Text("Thinking...")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal)
                        .id("loading")
                    }
                }
                .padding()
            }
            .onChange(of: viewModel.messages.count) {
                withAnimation {
                    if let last = viewModel.messages.last {
                        proxy.scrollTo(last.persistentModelID, anchor: .bottom)
                    }
                }
            }
            .onChange(of: viewModel.streamingText) {
                withAnimation {
                    proxy.scrollTo("streaming", anchor: .bottom)
                }
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
                        starterContext: nil,
                        availabilityContext: nil
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
}
