import Foundation

actor CoachService {
    static let shared = CoachService()

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
            "currentTime": ISO8601DateFormatter().string(from: Date()),
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
    let steps: [StepPayload]
    let temperatureReadings: [TempReadingPayload]
    let degreeHourTarget: Double
    let delays: [DelayPayload]

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
        let formatter = ISO8601DateFormatter()
        return [
            "recipeId": recipeId,
            "recipeName": recipeName,
            "hydrationPercent": hydrationPercent,
            "kitchenTempCelsius": kitchenTempCelsius,
            "targetBreadReadyTime": formatter.string(from: targetBreadReadyTime),
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
    }

    struct RevivalPayload {
        let isActive: Bool
        let currentStep: Int
        let totalSteps: Int
        let peakTimeTrend: [Double]
    }

    func toDictionary() -> [String: Any] {
        let formatter = ISO8601DateFormatter()
        var dict: [String: Any] = [
            "storageType": storageType,
            "maintenanceCycleDays": maintenanceCycleDays,
            "healthStatus": healthStatus,
            "daysSinceLastFeed": daysSinceLastFeed as Any,
            "recentFeeds": recentFeeds.map { feed in
                var d: [String: Any] = [
                    "timestamp": formatter.string(from: feed.timestamp),
                    "ratio": feed.ratio,
                    "flourType": feed.flourType,
                    "kitchenTempCelsius": feed.kitchenTempCelsius,
                ]
                d["timeToPeakMinutes"] = feed.timeToPeakMinutes as Any
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
        let formatter = ISO8601DateFormatter()
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
