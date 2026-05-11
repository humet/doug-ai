import Foundation
import SwiftData

@Model
final class CoachMessage {
    var role: String
    var content: String
    var timestamp: Date
    var schedule: Schedule?

    init(
        role: CoachMessageRole,
        content: String,
        schedule: Schedule? = nil
    ) {
        self.role = role.rawValue
        self.content = content
        timestamp = Date()
        self.schedule = schedule
    }

    var messageRole: CoachMessageRole {
        get { CoachMessageRole(rawValue: role) ?? .user }
        set { role = newValue.rawValue }
    }
}

enum CoachMessageRole: String, Codable {
    case user
    case assistant
}
