#if canImport(DougDomain)
@testable import DougDomain
#else
@testable import Doug
#endif
import Foundation
import Testing

struct LevainBuildPlannerTests {
    private let temp = 24.0

    private func choice(_ outcome: LevainBuildPlanner.Outcome) -> LevainBuildPlanner.Choice? {
        guard case let .build(choice) = outcome else { return nil }
        return choice
    }

    @Test func shortWindowPicksFastRatio() {
        // ~3.5h before the mix → a high-inoculation build that ripens quickly.
        let outcome = LevainBuildPlanner.selectBuild(
            windowMinutes: 210, kitchenTemp: temp, profile: nil
        )
        let c = try? #require(choice(outcome))
        #expect(c?.ratio == .oneToOne || c?.ratio == .oneToTwo)
        #expect(c?.classification == .standard)
        #expect(c?.holdMinutes == 0)
    }

    @Test func standardWindowPicksStandardRatio() {
        // ~5h window → the standard 1:5:5 build, ripe at mix.
        let outcome = LevainBuildPlanner.selectBuild(
            windowMinutes: 300, kitchenTemp: temp, profile: nil
        )
        let c = try? #require(choice(outcome))
        #expect(c?.ratio == .oneToFive)
        #expect(c?.classification == .standard)
        #expect(c?.holdMinutes == 0)
    }

    @Test func overnightWindowPicksSlowOvernightRatio() {
        // ~10h overnight gap → a low-inoculation overnight levain that peaks at mix.
        let outcome = LevainBuildPlanner.selectBuild(
            windowMinutes: 600, kitchenTemp: temp, profile: nil
        )
        let c = try? #require(choice(outcome))
        #expect(c?.ratio == .oneToTen)
        #expect(c?.classification == .overnight)
        #expect(c?.holdMinutes == 0)
    }

    @Test func ripenessStaysWithinPlateau() {
        // Whatever ratio is chosen, the mix lands inside [peak, peak + plateau].
        for window in stride(from: 200.0, through: 600.0, by: 25.0) {
            let outcome = LevainBuildPlanner.selectBuild(
                windowMinutes: window, kitchenTemp: temp, profile: nil
            )
            guard let c = choice(outcome), c.classification != .holdAfterPeak else { continue }
            #expect(c.peakMinutes <= window + 0.001)
            #expect(window <= c.peakMinutes + TemperatureCalculator.levainPlateauMinutes + 0.001)
        }
    }

    @Test func hugeWindowHoldsAfterPeak() {
        // A gap far beyond even an overnight build → build slow, then hold (chill).
        let outcome = LevainBuildPlanner.selectBuild(
            windowMinutes: 18 * 60, kitchenTemp: temp, profile: nil
        )
        let c = try? #require(choice(outcome))
        #expect(c?.classification == .holdAfterPeak)
        #expect((c?.holdMinutes ?? 0) > 0)
        #expect(c?.ratio == .oneToTen) // slowest available
    }

    @Test func holdIsCapped() {
        let outcome = LevainBuildPlanner.selectBuild(
            windowMinutes: 200 * 60, kitchenTemp: temp, profile: nil
        )
        let c = try? #require(choice(outcome))
        #expect(c?.holdMinutes == LevainBuildPlanner.maxHoldMinutes)
    }

    @Test func impossiblyShortWindowIsTooSoon() {
        // Shorter than the fastest levain can ripen → conflict.
        let outcome = LevainBuildPlanner.selectBuild(
            windowMinutes: 60, kitchenTemp: temp, profile: nil
        )
        #expect(outcome == .tooSoon)
    }

    @Test func observedProfileOverridesGenericEstimate() {
        // A baker whose 1:5:5 peaks fast (logged ~3h) should get 1:5:5 chosen for a
        // ~3h window where the generic model would've said it's too slow.
        let logs = (0 ..< 3).map { _ in
            FeedLogInput(
                timestamp: Date(),
                ratioStarter: 1, ratioFlour: 5, ratioWater: 5,
                flourType: "white",
                kitchenTemperatureCelsius: 24,
                timeToPeakMinutes: 180
            )
        }
        let profile = StarterPeakProfile(feedLogs: logs)
        let observed = LevainBuildPlanner.peakMinutes(ratio: .oneToFive, kitchenTemp: 24, profile: profile)
        #expect(abs(observed - 180) < 1)
    }
}
