import Foundation
import SwiftData

@Model
final class UserAvailability {
    var dailyStartHour: Int
    var dailyStartMinute: Int
    var dailyEndHour: Int
    var dailyEndMinute: Int

    init(
        dailyStartHour: Int = 6,
        dailyStartMinute: Int = 30,
        dailyEndHour: Int = 21,
        dailyEndMinute: Int = 0
    ) {
        self.dailyStartHour = dailyStartHour
        self.dailyStartMinute = dailyStartMinute
        self.dailyEndHour = dailyEndHour
        self.dailyEndMinute = dailyEndMinute
    }

    var dailyStartComponents: DateComponents {
        DateComponents(hour: dailyStartHour, minute: dailyStartMinute)
    }

    var dailyEndComponents: DateComponents {
        DateComponents(hour: dailyEndHour, minute: dailyEndMinute)
    }
}
