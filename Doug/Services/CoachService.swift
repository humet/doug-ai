import Foundation

actor CoachService {
    static let shared = CoachService()

    nonisolated static func makeLocalDateFormatter() -> ISO8601DateFormatter {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = .current
        return f
    }

    func streamResponse(
        messages: [(role: String, content: String)],
        bakeContext: BakeContextPayload?,
        starterContext: StarterContextPayload?,
        availabilityContext: AvailabilityContextPayload?
    ) -> AsyncThrowingStream<CoachStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    try await self.performStream(
                        messages: messages,
                        bakeContext: bakeContext,
                        starterContext: starterContext,
                        availabilityContext: availabilityContext,
                        continuation: continuation
                    )
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func performStream(
        messages: [(role: String, content: String)],
        bakeContext: BakeContextPayload?,
        starterContext: StarterContextPayload?,
        availabilityContext: AvailabilityContextPayload?,
        continuation: AsyncThrowingStream<CoachStreamEvent, Error>.Continuation
    ) async throws {
        guard let url = Config.coachAPIURL else {
            let offline = "I'm not available right now — the coach service isn't configured. " +
                "You can still check your schedule steps and timings in the app."
            continuation.yield(.text(offline))
            continuation.finish()
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = Config.coachAPIToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.timeoutInterval = 30

        let body: [String: Any] = [
            "messages": messages.map { ["role": $0.role, "content": $0.content] },
            "currentTime": Self.makeLocalDateFormatter().string(from: Date()),
            "timeZone": TimeZone.current.identifier,
            "context": bakeContext?.toDictionary() as Any,
            "starterContext": starterContext?.toDictionary() as Any,
            "availabilityContext": availabilityContext?.toDictionary() as Any,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw CoachError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            throw CoachError.serverError(httpResponse.statusCode)
        }

        for try await line in bytes.lines {
            guard line.hasPrefix("data: ") else { continue }
            let payload = String(line.dropFirst(6))
            if payload == "[DONE]" { break }
            guard let data = payload.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }

            if let text = json["text"] as? String {
                continuation.yield(.text(text))
            }
            if let actionDict = json["action"] as? [String: Any],
               let toolName = actionDict["toolName"] as? String,
               let params = actionDict["params"] as? [String: Any]
            {
                let proposal = CoachActionProposal.from(
                    toolName: toolName,
                    params: params
                )
                continuation.yield(.action(proposal))
            }
            if let error = json["error"] as? String {
                throw CoachError.streamError(error)
            }
        }

        continuation.finish()
    }
}

enum CoachStreamEvent {
    case text(String)
    case action(CoachActionProposal)
}

enum CoachError: LocalizedError {
    case invalidResponse
    case serverError(Int)
    case streamError(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "Couldn't reach the coach service."
        case let .serverError(code):
            "Coach service returned an error (\(code))."
        case let .streamError(message):
            message
        }
    }
}

// MARK: - Context Payloads

struct BakeContextPayload {
    let recipeId: String
    let recipeName: String
    let hydrationPercent: Int
    let kitchenTempCelsius: Double
    let targetBreadReadyTime: Date
    let recipeMethod: [RecipeMethodPayload]
    let recipeIngredients: IngredientsPayload
    let steps: [StepPayload]
    let temperatureReadings: [TempReadingPayload]
    let degreeHourTarget: Double
    let delays: [DelayPayload]

    struct RecipeMethodPayload {
        let stepTypeId: String
        let label: String
        let classification: String
        let baseDurationMinutes: Double
        let flexRangeMin: Double?
        let flexRangeMax: Double?
    }

    struct IngredientsPayload {
        let flourGrams: Double
        let waterGrams: Double
        let saltGrams: Double
        let levainGrams: Double
        /// Extras with their incorporation timing ("mix", "fold", or "topping")
        /// so the coach knows when each goes into the dough.
        let extras: [(name: String, grams: Double, incorporation: String)]
        /// Flour blend by type (e.g. whole wheat vs white). A single entry means
        /// the recipe doesn't specify a blend.
        let flourBreakdown: [(name: String, grams: Double)]
    }

    struct StepPayload {
        let stepTypeId: String
        let label: String
        let classification: String
        let status: String
        let computedStartTime: Date
        let computedEndTime: Date
        let durationMinutes: Double
        let flexRangeMin: Double?
        let flexRangeMax: Double?
    }

    struct TempReadingPayload {
        let timestamp: Date
        let temperatureCelsius: Double
        let accumulatedDegreeHours: Double
        let associatedStepTypeId: String?
    }

    struct DelayPayload {
        let stepLabel: String
        let delayMinutes: Double
    }

    func toDictionary() -> [String: Any] {
        let formatter = CoachService.makeLocalDateFormatter()
        return [
            "recipeId": recipeId,
            "recipeName": recipeName,
            "hydrationPercent": hydrationPercent,
            "kitchenTempCelsius": kitchenTempCelsius,
            "targetBreadReadyTime": formatter.string(from: targetBreadReadyTime),
            "recipeMethod": recipeMethod.map { m in
                var dict: [String: Any] = [
                    "stepTypeId": m.stepTypeId,
                    "label": m.label,
                    "classification": m.classification,
                    "baseDurationMinutes": m.baseDurationMinutes,
                ]
                if let min = m.flexRangeMin { dict["flexRangeMin"] = min }
                if let max = m.flexRangeMax { dict["flexRangeMax"] = max }
                return dict
            },
            "recipeIngredients": {
                var dict: [String: Any] = [
                    "flourGrams": recipeIngredients.flourGrams,
                    "waterGrams": recipeIngredients.waterGrams,
                    "saltGrams": recipeIngredients.saltGrams,
                    "levainGrams": recipeIngredients.levainGrams,
                ]
                if !recipeIngredients.extras.isEmpty {
                    dict["extras"] = recipeIngredients.extras.map {
                        ["name": $0.name, "grams": $0.grams, "incorporation": $0.incorporation] as [String: Any]
                    }
                }
                // Only send the breakdown for actual blends — a single flour
                // adds nothing over flourGrams.
                if recipeIngredients.flourBreakdown.count > 1 {
                    dict["flourBreakdown"] = recipeIngredients.flourBreakdown.map {
                        ["name": $0.name, "grams": $0.grams] as [String: Any]
                    }
                }
                return dict
            }(),
            "steps": steps.map { step in
                var dict: [String: Any] = [
                    "stepTypeId": step.stepTypeId,
                    "label": step.label,
                    "classification": step.classification,
                    "status": step.status,
                    "computedStartTime": formatter.string(from: step.computedStartTime),
                    "computedEndTime": formatter.string(from: step.computedEndTime),
                    "durationMinutes": step.durationMinutes,
                ]
                if let min = step.flexRangeMin { dict["flexRangeMin"] = min }
                if let max = step.flexRangeMax { dict["flexRangeMax"] = max }
                return dict
            },
            "temperatureReadings": temperatureReadings.map { reading in
                var dict: [String: Any] = [
                    "timestamp": formatter.string(from: reading.timestamp),
                    "temperatureCelsius": reading.temperatureCelsius,
                    "accumulatedDegreeHours": reading.accumulatedDegreeHours,
                ]
                if let id = reading.associatedStepTypeId { dict["associatedStepTypeId"] = id }
                return dict
            },
            "degreeHourTarget": degreeHourTarget,
            "delays": delays.map {
                ["stepLabel": $0.stepLabel, "delayMinutes": $0.delayMinutes] as [String: Any]
            },
        ]
    }
}

struct StarterContextPayload {
    let storageType: String
    let lifecycleState: String
    let maintenanceCycleDays: Double
    let healthStatus: String
    let daysSinceLastFeed: Double?
    let recentFeeds: [FeedPayload]
    let revivalPlan: RevivalPayload?

    struct FeedPayload {
        let timestamp: Date
        let ratio: String
        let flourType: String
        let kitchenTempCelsius: Double
        let timeToPeakMinutes: Double?
        let intent: String
        let starterGrams: Double?
        let flourGrams: Double?
        let waterGrams: Double?
    }

    struct RevivalPayload {
        let isActive: Bool
        let currentStep: Int
        let totalSteps: Int
        let peakTimeTrend: [Double]
    }

    func toDictionary() -> [String: Any] {
        let formatter = CoachService.makeLocalDateFormatter()
        var dict: [String: Any] = [
            "storageType": storageType,
            "lifecycleState": lifecycleState,
            "maintenanceCycleDays": maintenanceCycleDays,
            "healthStatus": healthStatus,
            "daysSinceLastFeed": daysSinceLastFeed as Any,
            "recentFeeds": recentFeeds.map { feed in
                var d: [String: Any] = [
                    "timestamp": formatter.string(from: feed.timestamp),
                    "ratio": feed.ratio,
                    "flourType": feed.flourType,
                    "kitchenTempCelsius": feed.kitchenTempCelsius,
                    "intent": feed.intent,
                ]
                d["timeToPeakMinutes"] = feed.timeToPeakMinutes as Any
                if let sg = feed.starterGrams { d["starterGrams"] = sg }
                if let fg = feed.flourGrams { d["flourGrams"] = fg }
                if let wg = feed.waterGrams { d["waterGrams"] = wg }
                return d
            },
        ]
        if let rp = revivalPlan {
            dict["revivalPlan"] = [
                "isActive": rp.isActive,
                "currentStep": rp.currentStep,
                "totalSteps": rp.totalSteps,
                "peakTimeTrend": rp.peakTimeTrend,
            ] as [String: Any]
        } else {
            dict["revivalPlan"] = NSNull()
        }
        return dict
    }
}

struct AvailabilityContextPayload {
    let unavailableWindows: [WindowPayload]

    struct WindowPayload {
        let start: Date
        let end: Date
        let label: String?
    }

    func toDictionary() -> [String: Any] {
        let formatter = CoachService.makeLocalDateFormatter()
        return [
            "unavailableWindows": unavailableWindows.map { w in
                var dict: [String: Any] = [
                    "start": formatter.string(from: w.start),
                    "end": formatter.string(from: w.end),
                ]
                if let label = w.label { dict["label"] = label }
                return dict
            },
        ]
    }
}
