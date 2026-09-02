#if canImport(DougDomain)
    @testable import DougDomain
#else
    @testable import Doug
#endif
import Foundation
import Testing

struct StarterAveragesTests {
    func log(peak: Double?, intent: FeedIntent) -> FeedLogInput {
        FeedLogInput(
            timestamp: Date(timeIntervalSince1970: 1_750_000_000),
            ratioStarter: 1, ratioFlour: 5, ratioWater: 5,
            flourType: "white", kitchenTemperatureCelsius: 22,
            timeToPeakMinutes: peak, feedIntent: intent
        )
    }

    @Test func averagesSplitByIntent() {
        let result = StarterAverages.recompute(feedLogs: [
            log(peak: 300, intent: .activation),
            log(peak: 500, intent: .activation),
            log(peak: 700, intent: .maintenance),
        ])
        #expect(result.averageTimeToPeakMinutes == 500)
        #expect(result.activePeakAverageMinutes == 400)
    }

    @Test func implausibleReadingsAreExcluded() {
        let result = StarterAverages.recompute(feedLogs: [
            log(peak: 300, intent: .activation),
            log(peak: 28720, intent: .activation), // ~20-day artifact
            log(peak: 10, intent: .activation), // below plausible minimum
        ])
        #expect(result.averageTimeToPeakMinutes == 300)
        #expect(result.activePeakAverageMinutes == 300)
    }

    @Test func nilWhenNoPlausiblePeaks() {
        let result = StarterAverages.recompute(feedLogs: [
            log(peak: nil, intent: .activation),
            log(peak: 28720, intent: .maintenance),
        ])
        #expect(result.averageTimeToPeakMinutes == nil)
        #expect(result.activePeakAverageMinutes == nil)
    }
}
