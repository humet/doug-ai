import Foundation
import SwiftData

@Observable
@MainActor
final class CoachViewModel {
    var messages: [CoachMessage] = []
    var inputText = ""
    var isStreaming = false
    var streamingText = ""
    var pendingActions: [CoachActionProposal] = []
    var actionSelections: Set<UUID> = []
    var error: String?

    private var streamTask: Task<Void, Never>?

    func loadHistory(modelContext: ModelContext, schedule: Schedule?) {
        guard let schedule else {
            messages = []
            return
        }
        let scheduleID = schedule.persistentModelID
        let descriptor = FetchDescriptor<CoachMessage>(
            predicate: #Predicate { $0.schedule?.persistentModelID == scheduleID },
            sortBy: [SortDescriptor(\.timestamp)]
        )
        messages = (try? modelContext.fetch(descriptor)) ?? []
    }

    func send(
        modelContext: ModelContext,
        schedule: Schedule?,
        bakeContext: BakeContextPayload?,
        starterContext: StarterContextPayload?,
        availabilityContext: AvailabilityContextPayload?
    ) {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isStreaming else { return }

        let userMessage = CoachMessage(
            role: .user,
            content: text,
            schedule: schedule
        )
        modelContext.insert(userMessage)
        messages.append(userMessage)
        inputText = ""
        error = nil

        let history = messages.map { (role: $0.role, content: $0.content) }

        isStreaming = true
        streamingText = ""
        pendingActions = []
        actionSelections = []

        streamTask = Task {
            do {
                let stream = await CoachService.shared.streamResponse(
                    messages: history,
                    bakeContext: bakeContext,
                    starterContext: starterContext,
                    availabilityContext: availabilityContext
                )
                for try await event in stream {
                    switch event {
                    case let .text(chunk):
                        streamingText += chunk
                    case let .action(proposal):
                        pendingActions.append(proposal)
                        actionSelections.insert(proposal.id)
                    }
                }
                let assistantMessage = CoachMessage(
                    role: .assistant,
                    content: streamingText,
                    schedule: schedule,
                    actions: pendingActions.isEmpty ? nil : pendingActions
                )
                modelContext.insert(assistantMessage)
                messages.append(assistantMessage)
            } catch is CancellationError {
                // cancelled
            } catch {
                self.error = error.localizedDescription
            }
            streamingText = ""
            isStreaming = false
        }
    }

    func toggleAction(_ id: UUID) {
        if actionSelections.contains(id) {
            actionSelections.remove(id)
        } else {
            actionSelections.insert(id)
        }
    }

    func applyActions(
        schedule: Schedule?,
        scheduleViewModel: ScheduleViewModel,
        modelContext: ModelContext
    ) {
        let selected = pendingActions.filter { actionSelections.contains($0.id) }

        for action in selected {
            guard let schedule,
                  let stepTypeId = action.stepTypeId,
                  let stepTypeID = StepTypeID(rawValue: stepTypeId)
            else { continue }

            let step = schedule.steps.first {
                $0.stepTypeID == stepTypeID.rawValue && $0.parentStep == nil
            }

            switch action.toolName {
            case "adjustStepDuration":
                guard let step, let newDuration = action.newDurationMinutes else { break }
                let delta = newDuration - step.computedDurationMinutes
                if delta > 0 {
                    scheduleViewModel.extendStep(step, byMinutes: delta, modelContext: modelContext)
                } else if delta < 0 {
                    scheduleViewModel.shortenStep(step, byMinutes: -delta, modelContext: modelContext)
                }
            case "delayStep":
                guard let step, let minutes = action.delayMinutes else { break }
                scheduleViewModel.delayStep(step, byMinutes: minutes, modelContext: modelContext)
            case "skipStep":
                guard let step else { break }
                scheduleViewModel.skipStep(step, modelContext: modelContext)
            case "resolveConflicts":
                guard let adjustments = action.adjustments else { break }
                for adj in adjustments {
                    guard let adjStepTypeID = StepTypeID(rawValue: adj.stepTypeId),
                          let adjStep = schedule.steps.first(where: {
                              $0.stepTypeID == adjStepTypeID.rawValue && $0.parentStep == nil
                          })
                    else { continue }
                    let delta = adj.newDurationMinutes - adjStep.computedDurationMinutes
                    if delta > 0 {
                        scheduleViewModel.extendStep(adjStep, byMinutes: delta, modelContext: modelContext)
                    } else if delta < 0 {
                        scheduleViewModel.shortenStep(adjStep, byMinutes: -delta, modelContext: modelContext)
                    }
                }
            default:
                break
            }
        }

        resolveActionsOnLastMessage()
    }

    func dismissActions() {
        if let last = messages.last, last.messageRole == .assistant {
            last.actionsResolved = true
            last.actionsDismissed = true
        }
        pendingActions = []
        actionSelections = []
    }

    private func resolveActionsOnLastMessage() {
        if let last = messages.last, last.messageRole == .assistant {
            last.actionsResolved = true
        }
        pendingActions = []
        actionSelections = []
    }

    func cancelStream() {
        streamTask?.cancel()
        streamTask = nil
    }
}
