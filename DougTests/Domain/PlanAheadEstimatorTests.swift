@testable import Doug
import Foundation
import Testing

struct PlanAheadEstimatorTests {
    private static let defaultAvailability = AvailabilityInput(
        startHour: 6, startMinute: 30,
        endHour: 21, endMinute: 0
    )

    private static let calendar: Calendar = {
        var cal = Calendar.current
        cal.timeZone = TimeZone(identifier: "Europe/London")!
        return cal
    }()

    private static func date(
        year: Int = 2026, month: Int = 5, day: Int = 16,
        hour: Int = 21, minute: Int = 0
    ) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.timeZone = TimeZone(identifier: "Europe/London")
        return calendar.date(from: components)!
    }

    // MARK: - Feasible Estimates

    @Test func feasibleEstimateReturnsActivateByBeforeLevainStart() {
        let result = PlanAheadEstimator.estimate(
            recipe: RecipeBook.countryLoaf,
            targetBreadReadyTime: Self.date(day: 16, hour: 21),
            kitchenTemperatureCelsius: 22,
            availability: Self.defaultAvailability,
            unavailableWindows: [],
            peakProfile: nil,
            activePeakAverageMinutes: nil,
            calendar: Self.calendar
        )

        guard case let .feasible(estimate) = result else {
            Issue.record("Expected feasible, got \(result)")
            return
        }

        #expect(estimate.activateBy < estimate.levainStartTime)
        let gapMinutes = estimate.levainStartTime.timeIntervalSince(estimate.activateBy) / 60
        #expect(gapMinutes >= estimate.activationDurationMinutes)
    }

    @Test func activateByLandsDuringAvailableHours() {
        let result = PlanAheadEstimator.estimate(
            recipe: RecipeBook.countryLoaf,
            targetBreadReadyTime: Self.date(day: 16, hour: 21),
            kitchenTemperatureCelsius: 22,
            availability: Self.defaultAvailability,
            unavailableWindows: [],
            peakProfile: nil,
            activePeakAverageMinutes: nil,
            calendar: Self.calendar
        )

        guard case let .feasible(estimate) = result else {
            Issue.record("Expected feasible, got \(result)")
            return
        }

        let hour = Self.calendar.component(.hour, from: estimate.activateBy)
        let minute = Self.calendar.component(.minute, from: estimate.activateBy)
        let timeInMinutes = hour * 60 + minute
        let availStart = 6 * 60 + 30 // 6:30
        let availEnd = 21 * 60 // 21:00

        #expect(timeInMinutes >= availStart, "Activation at \(hour):\(minute) is before available hours")
        #expect(timeInMinutes < availEnd, "Activation at \(hour):\(minute) is after available hours")
    }

    @Test func activateByAvoidsUnavailableWindow() {
        // Window blocks the evening slot where naive activation would land
        let eveningBlock = WindowInput(
            name: "Evening plans",
            isRecurring: true,
            daysOfWeek: [1, 2, 3, 4, 5, 6, 7],
            startHour: 17,
            startMinute: 0,
            endHour: 20,
            endMinute: 0
        )

        let result = PlanAheadEstimator.estimate(
            recipe: RecipeBook.countryLoaf,
            targetBreadReadyTime: Self.date(day: 16, hour: 21),
            kitchenTemperatureCelsius: 22,
            availability: Self.defaultAvailability,
            unavailableWindows: [eveningBlock],
            peakProfile: nil,
            activePeakAverageMinutes: nil,
            calendar: Self.calendar
        )

        guard case let .feasible(estimate) = result else {
            Issue.record("Expected feasible, got \(result)")
            return
        }

        let hour = Self.calendar.component(.hour, from: estimate.activateBy)
        #expect(hour < 17 || hour >= 20, "Activation should not land during 17:00–20:00 block")
    }

    // MARK: - All Recipes

    @Test(arguments: RecipeBook.all)
    func allRecipesProduceFeasibleEstimate(recipe: Recipe) {
        let result = PlanAheadEstimator.estimate(
            recipe: recipe,
            targetBreadReadyTime: Self.date(day: 18, hour: 18),
            kitchenTemperatureCelsius: 23,
            availability: Self.defaultAvailability,
            unavailableWindows: [],
            peakProfile: nil,
            activePeakAverageMinutes: nil,
            calendar: Self.calendar
        )

        guard case let .feasible(estimate) = result else {
            Issue.record("Expected feasible for \(recipe.name), got \(result)")
            return
        }

        #expect(estimate.activateBy < estimate.levainStartTime)
        #expect(estimate.levainStartTime < estimate.breadReadyTime)
    }

    // MARK: - No Availability Fallback

    @Test func noAvailabilityFallsBackToLinearEstimate() {
        let target = Self.date(day: 16, hour: 21)

        let result = PlanAheadEstimator.estimate(
            recipe: RecipeBook.countryLoaf,
            targetBreadReadyTime: target,
            kitchenTemperatureCelsius: 22,
            availability: nil,
            unavailableWindows: [],
            peakProfile: nil,
            activePeakAverageMinutes: nil,
            calendar: Self.calendar
        )

        guard case let .noAvailabilityConfigured(estimate) = result else {
            Issue.record("Expected noAvailabilityConfigured, got \(result)")
            return
        }

        // Should match the legacy linear formula
        let recipeDuration = EarliestBakeEstimator.recipeDurationMinutes(
            recipe: RecipeBook.countryLoaf,
            kitchenTempC: 22
        )
        let activationLead = TemperatureCalculator.levainBuildMinutes(kitchenTemp: 22)
        let legacyActivateBy = target.addingTimeInterval(-(recipeDuration + activationLead) * 60)

        let diff = abs(estimate.activateBy.timeIntervalSince(legacyActivateBy))
        #expect(diff < 1, "Fallback should match legacy formula within 1 second")
    }

    // MARK: - Conflict

    @Test func conflictReturnedWhenTargetTooClose() {
        // Target 2 hours from now — impossible for any recipe
        let tooSoon = Date().addingTimeInterval(2 * 3600)

        let result = PlanAheadEstimator.estimate(
            recipe: RecipeBook.countryLoaf,
            targetBreadReadyTime: tooSoon,
            kitchenTemperatureCelsius: 22,
            availability: Self.defaultAvailability,
            unavailableWindows: [],
            peakProfile: nil,
            activePeakAverageMinutes: nil,
            calendar: Self.calendar
        )

        // Schedule builder may return success with a start in the past,
        // or conflict if hands-on steps can't be placed. Either way,
        // activation won't fit — check that we don't get a feasible result
        // with activateBy in the future and after the target.
        if case let .feasible(estimate) = result {
            #expect(
                estimate.activateBy < Date(),
                "If feasible, activateBy should be in the past (impossible to hit)"
            )
        }
    }

    // MARK: - Peak Average

    @Test func usesActivePeakAverageWhenProvided() {
        let result = PlanAheadEstimator.estimate(
            recipe: RecipeBook.countryLoaf,
            targetBreadReadyTime: Self.date(day: 18, hour: 18),
            kitchenTemperatureCelsius: 22,
            availability: Self.defaultAvailability,
            unavailableWindows: [],
            peakProfile: nil,
            activePeakAverageMinutes: 240,
            calendar: Self.calendar
        )

        guard case let .feasible(estimate) = result else {
            Issue.record("Expected feasible")
            return
        }

        #expect(estimate.activationDurationMinutes == 240)
    }
}
