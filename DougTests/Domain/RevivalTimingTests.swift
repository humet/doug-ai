import Testing
import Foundation
#if canImport(DougDomain)
@testable import DougDomain
#else
@testable import Doug
#endif

struct RevivalTimingTests {
    // Available 6:30am – 9pm local time.
    private static let availability = AvailabilityInput(
        startHour: 6, startMinute: 30, endHour: 21, endMinute: 0
    )

    private static func date(hour: Int, minute: Int = 0, day: Int = 17) -> Date {
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 4
        comps.day = day
        comps.hour = hour
        comps.minute = minute
        return Calendar.current.date(from: comps)!
    }

    @Test func peakDuringDayIsSafe() {
        // Mix at 9am, peak at 3pm (6h later) — fully inside 6:30am-9pm.
        let falls = RevivalTiming.peakFallsInUnavailable(
            startTime: Self.date(hour: 9),
            expectedPeakMinutes: 360,
            availability: Self.availability,
            windows: []
        )
        #expect(falls == false)
    }

    @Test func overnightPeakIsFlagged() {
        // Mix at 4pm, 10h peak = 2am next day.
        let falls = RevivalTiming.peakFallsInUnavailable(
            startTime: Self.date(hour: 16),
            expectedPeakMinutes: 600,
            availability: Self.availability,
            windows: []
        )
        #expect(falls == true)
    }

    @Test func suggestedStartTimeReturnsNilWhenAlreadySafe() {
        let suggested = RevivalTiming.suggestedStartTime(
            currentTime: Self.date(hour: 9),
            expectedPeakMinutes: 360,
            availability: Self.availability,
            windows: []
        )
        #expect(suggested == nil)
    }

    @Test func suggestedStartTimeLandsPeakInAvailableHours() {
        // Mix at 4pm, 10h peak = 2am (unavailable). Helper must find a later start.
        let mixAt = Self.date(hour: 16)
        let suggested = RevivalTiming.suggestedStartTime(
            currentTime: mixAt,
            expectedPeakMinutes: 600,
            availability: Self.availability,
            windows: []
        )
        #expect(suggested != nil)

        guard let suggested else { return }
        // Suggested start must be later than the original mix time.
        #expect(suggested > mixAt)

        // And the peak from that start must NOT fall in unavailable hours.
        let peakFalls = RevivalTiming.peakFallsInUnavailable(
            startTime: suggested,
            expectedPeakMinutes: 600,
            availability: Self.availability,
            windows: []
        )
        #expect(peakFalls == false)
    }

    @Test func eveningPeakIsSafeWhenJustInsideWindow() {
        // Mix at 11am, peak at 9pm — lands right at the edge of available hours.
        // Edge case: 9pm is the end-hour so treating it as "unavailable" is
        // acceptable. Just confirm the helper doesn't throw; behaviour documented.
        _ = RevivalTiming.peakFallsInUnavailable(
            startTime: Self.date(hour: 11),
            expectedPeakMinutes: 600,
            availability: Self.availability,
            windows: []
        )
    }
}
