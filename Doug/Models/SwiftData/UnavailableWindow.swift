import Foundation
import SwiftData

@Model
final class UnavailableWindow {
    var name: String
    var isRecurring: Bool
    var daysOfWeek: [Int]
    var startHour: Int
    var startMinute: Int
    var endHour: Int
    var endMinute: Int
    var specificDate: Date?
    var isActive: Bool

    init(
        name: String,
        isRecurring: Bool = true,
        daysOfWeek: [Int] = [],
        startHour: Int,
        startMinute: Int,
        endHour: Int,
        endMinute: Int,
        specificDate: Date? = nil
    ) {
        self.name = name
        self.isRecurring = isRecurring
        self.daysOfWeek = daysOfWeek
        self.startHour = startHour
        self.startMinute = startMinute
        self.endHour = endHour
        self.endMinute = endMinute
        self.specificDate = specificDate
        self.isActive = true
    }

    var startComponents: DateComponents {
        DateComponents(hour: startHour, minute: startMinute)
    }

    var endComponents: DateComponents {
        DateComponents(hour: endHour, minute: endMinute)
    }
}
