#if canImport(DougDomain)
@testable import DougDomain
#else
@testable import Doug
#endif
import Foundation
import Testing

struct DegreeHourCalibratorTests {
    private let recipeID = RecipeBook.countryLoaf.id
    private let recipeTarget = RecipeBook.countryLoaf.degreeHourTarget
    private let start = Date(timeIntervalSince1970: 1_000_000)

    private func input(
        finalDegreeHours: Double,
        daysAgo: Double = 0,
        rating: Int = 5,
        note: String? = nil,
        recipeID: RecipeID? = nil
    ) -> BakeProfileInput {
        BakeProfileInput(
            recipeID: recipeID ?? self.recipeID,
            finalDegreeHours: finalDegreeHours,
            completedAt: start.addingTimeInterval(-daysAgo * 86400),
            rating: rating,
            outcomeNote: note
        )
    }

    @Test func returnsNilBelowMinimumGoodBakes() {
        let profiles = [
            input(finalDegreeHours: recipeTarget, daysAgo: 2),
            input(finalDegreeHours: recipeTarget, daysAgo: 1),
        ]
        #expect(DegreeHourCalibrator.refinedTarget(recipeID: recipeID, profiles: profiles) == nil)
    }

    @Test func refinesFromThreeGoodBakes() throws {
        let profiles = [
            input(finalDegreeHours: recipeTarget + 5, daysAgo: 3),
            input(finalDegreeHours: recipeTarget + 5, daysAgo: 2),
            input(finalDegreeHours: recipeTarget + 5, daysAgo: 1),
        ]
        let refined = try #require(DegreeHourCalibrator.refinedTarget(recipeID: recipeID, profiles: profiles))
        #expect(abs(refined - (recipeTarget + 5)) < 0.001)
    }

    @Test func lowRatedBakesExcluded() {
        let profiles = [
            input(finalDegreeHours: recipeTarget, daysAgo: 3),
            input(finalDegreeHours: recipeTarget, daysAgo: 2),
            input(finalDegreeHours: recipeTarget, daysAgo: 1, rating: 2),
        ]
        #expect(DegreeHourCalibrator.refinedTarget(recipeID: recipeID, profiles: profiles) == nil)
    }

    @Test func unratedFallsBackToNoteKeywords() {
        let profiles = [
            input(finalDegreeHours: recipeTarget, daysAgo: 3, rating: 0, note: "Really good crumb"),
            input(finalDegreeHours: recipeTarget, daysAgo: 2, rating: 0, note: "great oven spring"),
            input(finalDegreeHours: recipeTarget, daysAgo: 1, rating: 0, note: "dense and gummy"),
        ]
        // Only two qualify via keywords — below the minimum.
        #expect(DegreeHourCalibrator.refinedTarget(recipeID: recipeID, profiles: profiles) == nil)

        let withThird = profiles + [input(finalDegreeHours: recipeTarget, daysAgo: 0.5, rating: 0, note: "perfect")]
        #expect(DegreeHourCalibrator.refinedTarget(recipeID: recipeID, profiles: withThird) != nil)
    }

    @Test func implausibleFinalDegreeHoursExcluded() {
        // A junk record (e.g. bulk left running overnight) far outside the
        // plausible band must not drag the target.
        let profiles = [
            input(finalDegreeHours: recipeTarget, daysAgo: 3),
            input(finalDegreeHours: recipeTarget, daysAgo: 2),
            input(finalDegreeHours: recipeTarget * 4, daysAgo: 1),
        ]
        #expect(DegreeHourCalibrator.refinedTarget(recipeID: recipeID, profiles: profiles) == nil)
    }

    @Test func otherRecipesExcluded() throws {
        let other = try #require(RecipeBook.all.first { $0.id != recipeID })
        let profiles = [
            input(finalDegreeHours: recipeTarget, daysAgo: 3),
            input(finalDegreeHours: recipeTarget, daysAgo: 2),
            input(finalDegreeHours: recipeTarget, daysAgo: 1, recipeID: other.id),
        ]
        #expect(DegreeHourCalibrator.refinedTarget(recipeID: recipeID, profiles: profiles) == nil)
    }

    @Test func refinedTargetClampsToTwentyPercentOfRecipeDefault() throws {
        // Plausible-but-extreme histories may nudge the target, never yank it:
        // values inside the admission band still clamp to ±20% of the default.
        let high = [
            input(finalDegreeHours: recipeTarget * 1.8, daysAgo: 3),
            input(finalDegreeHours: recipeTarget * 1.8, daysAgo: 2),
            input(finalDegreeHours: recipeTarget * 1.8, daysAgo: 1),
        ]
        let refinedHigh = try #require(DegreeHourCalibrator.refinedTarget(recipeID: recipeID, profiles: high))
        #expect(abs(refinedHigh - recipeTarget * 1.2) < 0.001)

        let low = [
            input(finalDegreeHours: recipeTarget * 0.6, daysAgo: 3),
            input(finalDegreeHours: recipeTarget * 0.6, daysAgo: 2),
            input(finalDegreeHours: recipeTarget * 0.6, daysAgo: 1),
        ]
        let refinedLow = try #require(DegreeHourCalibrator.refinedTarget(recipeID: recipeID, profiles: low))
        #expect(abs(refinedLow - recipeTarget * 0.8) < 0.001)
    }

    @Test func recentBakesWeighHigherRegardlessOfInputOrder() throws {
        // Oldest→newest values 70, 80, 90 with linear weights 1/3, 2/3, 3/3:
        // (70×1 + 80×2 + 90×3) / 6 = 83.33 — pulled above the simple mean of 80.
        let oldest = input(finalDegreeHours: 70, daysAgo: 3)
        let middle = input(finalDegreeHours: 80, daysAgo: 2)
        let newest = input(finalDegreeHours: 90, daysAgo: 1)

        let sorted = try #require(
            DegreeHourCalibrator.refinedTarget(recipeID: recipeID, profiles: [oldest, middle, newest])
        )
        let shuffled = try #require(
            DegreeHourCalibrator.refinedTarget(recipeID: recipeID, profiles: [newest, oldest, middle])
        )
        #expect(abs(sorted - 83.333) < 0.01)
        #expect(sorted == shuffled)
    }
}
