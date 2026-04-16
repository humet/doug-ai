import Foundation

/// Resolves schedule conflicts using the Anthropic Claude API.
///
/// One-shot: sends conflict data, receives 2-3 ranked options with
/// baking-relevant explanations. No conversational follow-up.
actor LLMService {
    private let apiKey: String?

    init(apiKey: String? = Config.anthropicAPIKey) {
        self.apiKey = apiKey
    }

    var isAvailable: Bool {
        Config.hasAPIKey
    }

    /// Resolves a schedule conflict by asking Claude for alternatives.
    ///
    /// - Parameters:
    ///   - conflict: The conflict details from the scheduler.
    ///   - recipe: The recipe being scheduled.
    ///   - kitchenTemp: The user's kitchen temperature.
    /// - Returns: Array of ranked options, or empty if offline/unavailable.
    func resolveConflict(
        _ conflict: ScheduleConflict,
        recipe: Recipe,
        kitchenTemp: Double
    ) async throws -> [ConflictOption] {
        guard let apiKey, !apiKey.isEmpty, apiKey != "YOUR_ANTHROPIC_API_KEY" else {
            return offlineFallback(conflict)
        }

        let prompt = buildPrompt(conflict: conflict, recipe: recipe, kitchenTemp: kitchenTemp)

        let requestBody: [String: Any] = [
            "model": "claude-sonnet-4-5-20250514",
            "max_tokens": 300,
            "messages": [
                ["role": "user", "content": prompt],
            ],
        ]

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200
        else {
            return offlineFallback(conflict)
        }

        return parseResponse(data: data, conflict: conflict)
    }

    // MARK: - Prompt Construction

    private func buildPrompt(
        conflict: ScheduleConflict,
        recipe: Recipe,
        kitchenTemp: Double
    ) -> String {
        """
        You are a sourdough baking assistant. A schedule conflict occurred.

        Recipe: \(recipe.name) (\(recipe.hydrationPercent)% hydration)
        Kitchen temperature: \(Int(kitchenTemp))°C
        Conflict: \(conflict.conflictingStepLabel) overlaps with \(conflict.conflictingWindowName)

        \(conflict.message)

        Suggest 2-3 ranked alternatives. For each:
        - A short summary (one sentence)
        - A brief explanation of baking tradeoffs

        Format each option as:
        OPTION: [summary]
        EXPLANATION: [tradeoffs]

        Keep responses concise. Focus on practical scheduling adjustments.
        """
    }

    // MARK: - Response Parsing

    private func parseResponse(data: Data, conflict: ScheduleConflict) -> [ConflictOption] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let firstBlock = content.first,
              let text = firstBlock["text"] as? String
        else {
            return offlineFallback(conflict)
        }

        // Parse OPTION/EXPLANATION pairs from the text
        var options: [ConflictOption] = []
        let lines = text.components(separatedBy: "\n")
        var currentSummary: String?

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("OPTION:") {
                currentSummary = String(trimmed.dropFirst(7)).trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("EXPLANATION:"), let summary = currentSummary {
                let explanation = String(trimmed.dropFirst(12)).trimmingCharacters(in: .whitespaces)
                options.append(ConflictOption(
                    summary: summary,
                    explanation: explanation
                ))
                currentSummary = nil
            }
        }

        return options.isEmpty ? offlineFallback(conflict) : options
    }

    // MARK: - Offline Fallback

    private func offlineFallback(_ conflict: ScheduleConflict) -> [ConflictOption] {
        var options: [ConflictOption] = []

        if let altTime = conflict.suggestedAlternativeTime {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            let timeStr = formatter.string(from: altTime)

            options.append(ConflictOption(
                summary: "Move \(conflict.conflictingStepLabel) to \(timeStr)",
                explanation: "Shifts the step to avoid the conflict. Downstream steps adjust automatically."
            ))
        }

        options.append(ConflictOption(
            summary: "Try a different bread-ready time",
            explanation: "Adjusting when you want bread ready may clear the conflict entirely."
        ))

        return options
    }
}

// MARK: - Conflict Option

struct ConflictOption: Identifiable, Sendable {
    let id = UUID()
    let summary: String
    let explanation: String
}
