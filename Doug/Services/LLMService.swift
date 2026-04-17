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

    /// Composes personalised instruction copy for a revival plan.
    ///
    /// Plan structure (step count, grams, expected timings) is fixed by the caller —
    /// this method only fills in the human-readable copy. Returns nil when offline,
    /// when the key is missing, when the model replies ABORT (a self-check on the
    /// user's free-text for contamination signals), or when parsing fails. Callers
    /// must fall back to `FeedInstructions` templates in those cases.
    func composeRevivalCoaching(_ request: RevivalCoachingRequest) async -> RevivalCoaching? {
        guard let apiKey, !apiKey.isEmpty, apiKey != "YOUR_ANTHROPIC_API_KEY" else {
            return nil
        }

        let prompt = buildRevivalPrompt(request)

        let requestBody: [String: Any] = [
            "model": "claude-sonnet-4-5-20250514",
            "max_tokens": 900,
            "messages": [
                ["role": "user", "content": prompt],
            ],
        ]

        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else { return nil }
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.timeoutInterval = 15

        do {
            urlRequest.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
            let (data, response) = try await URLSession.shared.data(for: urlRequest)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return nil
            }
            return Self.parseRevivalResponse(data: data, stepCount: request.steps.count)
        } catch {
            return nil
        }
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

    private func buildRevivalPrompt(_ request: RevivalCoachingRequest) -> String {
        let neglect = request.neglect.rawValue
        let hoochLine = request.hadHooch ? "Yes" : "No"
        let daysLine = request.daysSinceLastFed.map { "\($0)" } ?? "unknown"
        let notesLine = (request.userNotes?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap {
            $0.isEmpty ? nil : $0
        } ?? "(none)"

        let stepLines = request.steps.map { step in
            let kind = switch step.kind {
            case .revivalFirst: "first"
            case .revivalMiddle: "middle"
            case .revivalFinal: "final"
            case .maintenance: "maintenance"
            }
            return """
            Step \(step.sequenceIndex) (\(kind)): retain \(Int(step.retainGrams.rounded())) g, \
            add \(Int(step.addFlourGrams.rounded())) g flour, \
            add \(Int(step.addWaterGrams.rounded())) g water, \
            expected peak \(Int(step.expectedPeakMinutes.rounded())) min.
            """
        }.joined(separator: "\n")

        return """
        You are a sourdough baking coach writing step-by-step instructions \
        for a user reviving a neglected starter.

        The gram amounts, retain amounts, and step count are FIXED — \
        do not change them or suggest alternatives. \
        You are only writing the human-readable instructional copy.

        If the user's free-text notes describe pink, orange, red, fuzzy, or \
        visibly mouldy growth, reply with only the single word ABORT and \
        nothing else, so the app can surface a safety warning instead.

        Starter status:
        - Neglect level: \(neglect)
        - Days since last fed: \(daysLine)
        - Hooch present: \(hoochLine)
        - Initial starter amount: \(Int(request.initialStarterGrams.rounded())) g
        - Flour type available: \(request.flourType)
        - Kitchen temperature: \(Int(request.kitchenTempC.rounded()))°C
        - User notes: \(notesLine)

        Plan (fixed):
        \(stepLines)

        Reply using EXACTLY this format, no markdown, no extra lines:

        OPENING: <one or two sentences reading the user's situation>
        STEP 0 TITLE: <short title>
        STEP 0 BULLETS: <bullet 1> | <bullet 2> | <bullet 3>
        STEP 0 WATCH: <what to look for at peak>
        STEP 0 WAIT: <expected wait, e.g. ~6 hours>
        STEP 1 TITLE: ...
        STEP 1 BULLETS: ...
        STEP 1 WATCH: ...
        STEP 1 WAIT: ...
        (continue for every step in the plan)

        Bullets must be separated by " | " on a single line. \
        Keep bullets imperative and concrete. \
        Mention gram amounts exactly as given in the plan. \
        Do not include step numbers outside of the prefix. \
        Keep the whole response tight — it will be shown inline in a mobile app.
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

    /// Parses the OPENING/STEP N prefix response into a `RevivalCoaching`.
    ///
    /// Exposed as `static` so tests can exercise parsing without standing up the actor
    /// or hitting the network.
    static func parseRevivalResponse(data: Data, stepCount: Int) -> RevivalCoaching? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let firstBlock = content.first,
              let text = firstBlock["text"] as? String
        else {
            return nil
        }
        return parseRevivalText(text, stepCount: stepCount)
    }

    static func parseRevivalText(_ text: String, stepCount: Int) -> RevivalCoaching? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "ABORT" || trimmed.hasPrefix("ABORT\n") || trimmed.hasPrefix("ABORT ") {
            return nil
        }

        var opening: String?
        var titles: [Int: String] = [:]
        var bullets: [Int: [String]] = [:]
        var watchFor: [Int: String] = [:]
        var waits: [Int: String] = [:]

        for line in trimmed.components(separatedBy: "\n") {
            let raw = line.trimmingCharacters(in: .whitespaces)
            guard !raw.isEmpty else { continue }

            if raw.uppercased().hasPrefix("OPENING:") {
                opening = String(raw.dropFirst("OPENING:".count)).trimmingCharacters(in: .whitespaces)
                continue
            }

            // STEP N TITLE: / BULLETS: / WATCH: / WAIT:
            let upper = raw.uppercased()
            guard upper.hasPrefix("STEP ") else { continue }
            let afterStep = raw.dropFirst("STEP ".count)
            guard let spaceIdx = afterStep.firstIndex(of: " "),
                  let index = Int(afterStep[..<spaceIdx])
            else { continue }
            let afterIndex = afterStep[afterStep.index(after: spaceIdx)...]
            guard let colonIdx = afterIndex.firstIndex(of: ":") else { continue }
            let field = afterIndex[..<colonIdx].uppercased()
            let value = String(afterIndex[afterIndex.index(after: colonIdx)...]).trimmingCharacters(in: .whitespaces)

            switch field.trimmingCharacters(in: .whitespaces) {
            case "TITLE":
                titles[index] = value
            case "BULLETS":
                bullets[index] = value
                    .components(separatedBy: "|")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
            case "WATCH":
                watchFor[index] = value
            case "WAIT":
                waits[index] = value
            default:
                continue
            }
        }

        guard let opening, !opening.isEmpty else { return nil }

        var coachedSteps: [CoachedStep] = []
        for i in 0 ..< stepCount {
            guard let title = titles[i], !title.isEmpty,
                  let stepBullets = bullets[i], !stepBullets.isEmpty,
                  let watch = watchFor[i], !watch.isEmpty,
                  let wait = waits[i], !wait.isEmpty
            else {
                return nil
            }
            coachedSteps.append(CoachedStep(
                sequenceIndex: i,
                title: title,
                bullets: stepBullets,
                watchFor: watch,
                expectedWait: wait
            ))
        }

        return RevivalCoaching(openingRead: opening, steps: coachedSteps)
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

struct ConflictOption: Identifiable {
    let id = UUID()
    let summary: String
    let explanation: String
    let targetTimeShiftMinutes: Double?

    init(
        summary: String,
        explanation: String,
        targetTimeShiftMinutes: Double? = nil
    ) {
        self.summary = summary
        self.explanation = explanation
        self.targetTimeShiftMinutes = targetTimeShiftMinutes
    }
}

// MARK: - Revival Coaching

struct RevivalCoachingRequest {
    let neglect: StarterNeglectLevel
    let hadHooch: Bool
    let daysSinceLastFed: Int?
    let initialStarterGrams: Double
    let flourType: String
    let kitchenTempC: Double
    let userNotes: String?
    let steps: [PlannedStep]
}

struct PlannedStep {
    let sequenceIndex: Int
    let retainGrams: Double
    let addFlourGrams: Double
    let addWaterGrams: Double
    let expectedPeakMinutes: Double
    let kind: FeedStepKind
}

struct RevivalCoaching: Equatable {
    let openingRead: String
    let steps: [CoachedStep]
}

struct CoachedStep: Equatable {
    let sequenceIndex: Int
    let title: String
    let bullets: [String]
    let watchFor: String
    let expectedWait: String
}
