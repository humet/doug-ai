#if canImport(DougDomain)
@testable import DougDomain
#else
@testable import Doug
#endif
import Foundation
import Testing

struct RevivalReschedulerTests {
    @Test func peakInsideToleranceReturnsZero() {
        let scheduled = Date()
        let started = scheduled.addingTimeInterval(60)
        // Expected 300 min (5h), tolerance [225, 450]. Actual = 250 min → inside.
        let peakAt = started.addingTimeInterval(250 * 60)
        let delta = RevivalRescheduler.peakDelta(
            scheduledTime: scheduled,
            startedAt: started,
            peakAt: peakAt,
            expectedPeakMinutes: 300,
            minPeakMinutes: 225,
            maxPeakMinutes: 450
        )
        #expect(delta == 0)
    }

    @Test func peakBeyondToleranceReturnsDeltaToExpected() {
        let scheduled = Date()
        let started = scheduled.addingTimeInterval(60)
        // Expected 300, tolerance [225, 450]. Actual = 500 min → delta = (500 - 300) * 60.
        let peakAt = started.addingTimeInterval(500 * 60)
        let delta = RevivalRescheduler.peakDelta(
            scheduledTime: scheduled,
            startedAt: started,
            peakAt: peakAt,
            expectedPeakMinutes: 300,
            minPeakMinutes: 225,
            maxPeakMinutes: 450
        )
        #expect(delta == 200 * 60)
    }

    @Test func peakEarlyReturnsNegativeDelta() {
        let scheduled = Date()
        let started = scheduled
        // Expected 300, tolerance [225, 450]. Actual = 180 min → delta = -120 min.
        let peakAt = started.addingTimeInterval(180 * 60)
        let delta = RevivalRescheduler.peakDelta(
            scheduledTime: scheduled,
            startedAt: started,
            peakAt: peakAt,
            expectedPeakMinutes: 300,
            minPeakMinutes: 225,
            maxPeakMinutes: 450
        )
        #expect(delta == -120 * 60)
    }

    @Test func startInGraceWindowReturnsZero() {
        let scheduled = Date()
        // 20 min late, grace is 30 → no delta.
        let delta = RevivalRescheduler.startDelta(
            scheduledTime: scheduled,
            startedAt: scheduled.addingTimeInterval(20 * 60),
            graceMinutes: 30
        )
        #expect(delta == 0)
    }

    @Test func startBeyondGraceReturnsExcessLateness() {
        let scheduled = Date()
        // 45 min late, grace is 30 → delta = 15 min.
        let delta = RevivalRescheduler.startDelta(
            scheduledTime: scheduled,
            startedAt: scheduled.addingTimeInterval(45 * 60),
            graceMinutes: 30
        )
        #expect(delta == 15 * 60)
    }

    @Test func startOnTimeReturnsZero() {
        let scheduled = Date()
        let delta = RevivalRescheduler.startDelta(
            scheduledTime: scheduled,
            startedAt: scheduled,
            graceMinutes: 30
        )
        #expect(delta == 0)
    }
}
