import Foundation
import SwiftData

@Observable
@MainActor
final class CoachViewModel {
    var messages: [CoachMessage] = []
    var inputText = ""
    var isStreaming = false
    var streamingText = ""
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

        streamTask = Task {
            do {
                let stream = await CoachService.shared.streamResponse(
                    messages: history,
                    bakeContext: bakeContext,
                    starterContext: starterContext,
                    availabilityContext: availabilityContext
                )
                for try await chunk in stream {
                    streamingText += chunk
                }
                let assistantMessage = CoachMessage(
                    role: .assistant,
                    content: streamingText,
                    schedule: schedule
                )
                modelContext.insert(assistantMessage)
                messages.append(assistantMessage)
            } catch is CancellationError {
                // cancelled — no action needed
            } catch {
                self.error = error.localizedDescription
            }
            streamingText = ""
            isStreaming = false
        }
    }

    func cancelStream() {
        streamTask?.cancel()
        streamTask = nil
    }
}
