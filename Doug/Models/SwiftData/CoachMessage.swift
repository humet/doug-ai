import Foundation
import SwiftData

@Model
final class CoachMessage {
    var role: String
    var content: String
    var timestamp: Date
    var schedule: Schedule?
    var actionsJSON: String?
    var actionsResolved: Bool
    var actionsDismissed: Bool

    init(
        role: CoachMessageRole,
        content: String,
        schedule: Schedule? = nil,
        actions: [CoachActionProposal]? = nil
    ) {
        self.role = role.rawValue
        self.content = content
        timestamp = Date()
        self.schedule = schedule
        actionsResolved = false
        actionsDismissed = false
        if let actions, !actions.isEmpty {
            actionsJSON = try? String(
                data: JSONEncoder().encode(actions),
                encoding: .utf8
            )
        }
    }

    var messageRole: CoachMessageRole {
        get { CoachMessageRole(rawValue: role) ?? .user }
        set { role = newValue.rawValue }
    }

    var actions: [CoachActionProposal]? {
        guard let json = actionsJSON, let data = json.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder().decode([CoachActionProposal].self, from: data)
    }
}

enum CoachMessageRole: String, Codable {
    case user
    case assistant
}

struct CoachActionProposal: Codable, Identifiable {
    let id: UUID
    let toolName: String
    let reason: String
    let stepTypeId: String?
    let newDurationMinutes: Double?
    let delayMinutes: Double?
    let afterStepTypeId: String?
    let newStepLabel: String?
    let classification: String?
    let adjustments: [FlexAdjustment]?
    let ratio: String?
    let flourType: String?

    struct FlexAdjustment: Codable {
        let stepTypeId: String
        let newDurationMinutes: Double
    }

    var displaySummary: String {
        switch toolName {
        case "adjustStepDuration":
            let label = stepTypeId.map { StepTypeRegistry.type(for: StepTypeID(rawValue: $0)!).label } ?? "step"
            return "Change \(label) to \(Int(newDurationMinutes ?? 0))min"
        case "delayStep":
            let label = stepTypeId.map { StepTypeRegistry.type(for: StepTypeID(rawValue: $0)!).label } ?? "step"
            return "Delay \(label) by \(Int(delayMinutes ?? 0))min"
        case "skipStep":
            let label = stepTypeId.map { StepTypeRegistry.type(for: StepTypeID(rawValue: $0)!).label } ?? "step"
            return "Skip \(label)"
        case "addStep":
            return "Add \"\(newStepLabel ?? "step")\" (\(Int(newDurationMinutes ?? 0))min)"
        case "resolveConflicts":
            let count = adjustments?.count ?? 0
            return "Adjust \(count) step\(count == 1 ? "" : "s") to resolve conflicts"
        case "suggestFeedChange":
            return "Feed \(ratio ?? "") with \(flourType ?? "")"
        default:
            return reason
        }
    }

    static func from(toolName: String, params: [String: Any]) -> CoachActionProposal {
        CoachActionProposal(
            id: UUID(),
            toolName: toolName,
            reason: params["reason"] as? String ?? "",
            stepTypeId: params["stepTypeId"] as? String,
            newDurationMinutes: params["newDurationMinutes"] as? Double,
            delayMinutes: params["delayMinutes"] as? Double,
            afterStepTypeId: params["afterStepTypeId"] as? String,
            newStepLabel: params["newStepLabel"] as? String,
            classification: params["classification"] as? String,
            adjustments: (params["adjustments"] as? [[String: Any]])?.compactMap { adj in
                guard let stepId = adj["stepTypeId"] as? String,
                      let dur = adj["newDurationMinutes"] as? Double
                else { return nil }
                return FlexAdjustment(stepTypeId: stepId, newDurationMinutes: dur)
            },
            ratio: params["ratio"] as? String,
            flourType: params["flourType"] as? String
        )
    }
}
