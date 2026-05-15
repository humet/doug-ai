#if canImport(DougDomain)
@testable import DougDomain
#else
@testable import Doug
#endif
import Foundation
import Testing

struct StarterHealthTests {
    private static let fridgeProfile = StarterProfileInput(
        storageType: .fridge,
        maintenanceCycleDays: 6,
        needsFeedDaysThreshold: 7,
        needsRevivalDaysThreshold: 10,
        averageTimeToPeakMinutes: 300
    )

    @Test func recentFeedIsReady() {
        let now = Date()
        let logs = [
            FeedLogInput(
                timestamp: now.addingTimeInterval(-86400), // 1 day ago
                ratioStarter: 1, ratioFlour: 5, ratioWater: 5,
                flourType: "white", kitchenTemperatureCelsius: 22,
                timeToPeakMinutes: 300
            ),
        ]

        let status = StarterHealthAssessor.assess(
            profile: Self.fridgeProfile,
            feedLogs: logs,
            now: now
        )
        #expect(status == .readyToBake)
    }

    @Test func moderatelyOverdueNeedsFeed() {
        let now = Date()
        let logs = [
            FeedLogInput(
                timestamp: now.addingTimeInterval(-8 * 86400), // 8 days ago
                ratioStarter: 1, ratioFlour: 5, ratioWater: 5,
                flourType: "white", kitchenTemperatureCelsius: 22,
                timeToPeakMinutes: 300
            ),
        ]

        let status = StarterHealthAssessor.assess(
            profile: Self.fridgeProfile,
            feedLogs: logs,
            now: now
        )
        #expect(status == .needsFeed)
    }

    @Test func significantlyOverdueNeedsRevival() {
        let now = Date()
        let logs = [
            FeedLogInput(
                timestamp: now.addingTimeInterval(-15 * 86400), // 15 days ago
                ratioStarter: 1, ratioFlour: 5, ratioWater: 5,
                flourType: "white", kitchenTemperatureCelsius: 22,
                timeToPeakMinutes: 300
            ),
        ]

        let status = StarterHealthAssessor.assess(
            profile: Self.fridgeProfile,
            feedLogs: logs,
            now: now
        )
        #expect(status == .needsRevival)
    }

    @Test func noFeedHistoryNeedsRevival() {
        let status = StarterHealthAssessor.assess(
            profile: Self.fridgeProfile,
            feedLogs: [],
            now: Date()
        )
        #expect(status == .needsRevival)
    }

    @Test func slowPeakTimeTriggerRevival() {
        let now = Date()
        // Peak times are >50% slower than historical average of 300 min
        let logs = [
            FeedLogInput(
                timestamp: now.addingTimeInterval(-86400),
                ratioStarter: 1, ratioFlour: 5, ratioWater: 5,
                flourType: "white", kitchenTemperatureCelsius: 22,
                timeToPeakMinutes: 500
            ),
            FeedLogInput(
                timestamp: now.addingTimeInterval(-2 * 86400),
                ratioStarter: 1, ratioFlour: 5, ratioWater: 5,
                flourType: "white", kitchenTemperatureCelsius: 22,
                timeToPeakMinutes: 480
            ),
        ]

        let status = StarterHealthAssessor.assess(
            profile: Self.fridgeProfile,
            feedLogs: logs,
            now: now
        )
        #expect(status == .needsRevival)
    }
}
