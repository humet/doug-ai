@testable import Doug
import Foundation
import Testing

@Suite struct UnavailableWindowTests {
    private let calendar = Calendar.current

    /// A fixed reference "now" so tests don't depend on the wall clock.
    private var reference: Date {
        calendar.date(from: DateComponents(year: 2026, month: 6, day: 4, hour: 14, minute: 30))!
    }

    private func oneOff(on date: Date?) -> UnavailableWindow {
        UnavailableWindow(
            name: "Dentist",
            isRecurring: false,
            startHour: 9, startMinute: 0,
            endHour: 10, endMinute: 0,
            specificDate: date
        )
    }

    @Test func oneOffDatedYesterdayIsExpired() {
        let yesterday = calendar.date(byAdding: .day, value: -1, to: reference)!
        #expect(oneOff(on: yesterday).hasExpired(asOf: reference))
    }

    @Test func oneOffEarlierTodayIsNotExpired() {
        // Same calendar day as the reference, but an earlier clock time —
        // expiry is keyed to the day boundary, not the hour.
        let earlierToday = calendar.startOfDay(for: reference)
        #expect(!oneOff(on: earlierToday).hasExpired(asOf: reference))
    }

    @Test func oneOffDatedTomorrowIsNotExpired() {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: reference)!
        #expect(!oneOff(on: tomorrow).hasExpired(asOf: reference))
    }

    @Test func oneOffWithoutDateIsNotExpired() {
        #expect(!oneOff(on: nil).hasExpired(asOf: reference))
    }

    @Test func recurringWindowNeverExpires() {
        // Even with a stale specificDate set, a recurring window repeats by
        // weekday and must never be treated as expired.
        let lastYear = calendar.date(byAdding: .year, value: -1, to: reference)!
        let window = UnavailableWindow(
            name: "Gym",
            isRecurring: true,
            daysOfWeek: [2, 4, 6],
            startHour: 17, startMinute: 30,
            endHour: 19, endMinute: 0,
            specificDate: lastYear
        )
        #expect(!window.hasExpired(asOf: reference))
    }

    @Test func expiryIsRelativeToReferenceDay() {
        // A window dated 2026-06-04 is not expired on the 4th, but is on the 5th.
        let window = oneOff(on: calendar.startOfDay(for: reference))
        let nextDay = calendar.date(byAdding: .day, value: 1, to: reference)!
        #expect(!window.hasExpired(asOf: reference))
        #expect(window.hasExpired(asOf: nextDay))
    }
}
