@testable import Doug
import Foundation
import Testing

struct ScheduleBuilderTests {
    // MARK: - Test Helpers

    private static let defaultAvailability = AvailabilityInput(
        startHour: 6, startMinute: 30,
        endHour: 21, endMinute: 0
    )

    private static func targetTime(
        year: Int = 2026, month: Int = 4, day: Int = 19,
        hour: Int = 9, minute: Int = 0
    ) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.timeZone = TimeZone(identifier: "Europe/London")
        return Calendar.current.date(from: components)!
    }

    // MARK: - Happy Path

    @Test func countryLoafProducesValidSchedule() throws {
        let input = ScheduleBuilderInput(
            recipe: RecipeBook.countryLoaf,
            targetBreadReadyTime: Self.targetTime(),
            kitchenTemperatureCelsius: 24.0,
            availability: Self.defaultAvailability
        )

        let result = ScheduleBuilder.build(input)

        guard case let .success(steps) = result else {
            Issue.record("Expected success, got conflict")
            return
        }

        #expect(!steps.isEmpty)
        #expect(steps.first?.stepTypeID == StepTypeID.buildLevain)
        #expect(steps.last?.stepTypeID == StepTypeID.bakeUncovered)

        // Steps should be in chronological order
        for i in 1 ..< steps.count {
            #expect(steps[i].startTime >= steps[i - 1].startTime)
        }

        // Last step should end at target time
        let lastEnd = try #require(steps.last?.endTime)
        let diff = abs(lastEnd.timeIntervalSince(Self.targetTime()))
        #expect(diff < 60)
    }

    @Test func bulkFermentContainsFolds() {
        let input = ScheduleBuilderInput(
            recipe: RecipeBook.countryLoaf,
            targetBreadReadyTime: Self.targetTime(),
            kitchenTemperatureCelsius: 24.0,
            availability: Self.defaultAvailability
        )

        guard case let .success(steps) = ScheduleBuilder.build(input) else {
            Issue.record("Expected success")
            return
        }

        let bulkStep = steps.first(where: { $0.stepTypeID == StepTypeID.bulkFerment })
        #expect(bulkStep != nil)
        #expect(bulkStep?.subSteps.count == 4) // country loaf has 4 folds
    }

    @Test func oliveRosemaryIncludesInclusionStep() {
        let input = ScheduleBuilderInput(
            recipe: RecipeBook.oliveRosemary,
            targetBreadReadyTime: Self.targetTime(),
            kitchenTemperatureCelsius: 24.0,
            availability: Self.defaultAvailability
        )

        guard case let .success(steps) = ScheduleBuilder.build(input) else {
            Issue.record("Expected success")
            return
        }

        let hasInclusions = steps.contains(where: { $0.stepTypeID == StepTypeID.addInclusions })
            || steps.flatMap(\.subSteps).contains(where: { $0.stepTypeID == StepTypeID.addInclusions })
        #expect(hasInclusions)
    }

    // MARK: - Temperature Variations

    @Test func hotKitchenProducesShorterSchedule() throws {
        let hotInput = ScheduleBuilderInput(
            recipe: RecipeBook.countryLoaf,
            targetBreadReadyTime: Self.targetTime(),
            kitchenTemperatureCelsius: 28.0,
            availability: Self.defaultAvailability
        )
        let coldInput = ScheduleBuilderInput(
            recipe: RecipeBook.countryLoaf,
            targetBreadReadyTime: Self.targetTime(),
            kitchenTemperatureCelsius: 18.0,
            availability: Self.defaultAvailability
        )

        guard case let .success(hotSteps) = ScheduleBuilder.build(hotInput),
              case let .success(coldSteps) = ScheduleBuilder.build(coldInput)
        else {
            Issue.record("Expected both to succeed")
            return
        }

        let hotStart = try #require(hotSteps.first?.startTime)
        let coldStart = try #require(coldSteps.first?.startTime)
        #expect(coldStart < hotStart)
    }

    // MARK: - All Recipes Build

    @Test(arguments: RecipeBook.all)
    func allRecipesBuildSuccessfully(recipe: Recipe) throws {
        let input = ScheduleBuilderInput(
            recipe: recipe,
            targetBreadReadyTime: Self.targetTime(),
            kitchenTemperatureCelsius: 22.0,
            availability: Self.defaultAvailability
        )

        let result = ScheduleBuilder.build(input)
        guard case let .success(steps) = result else {
            Issue.record("Recipe '\(recipe.name)' failed to build schedule")
            return
        }

        #expect(!steps.isEmpty)
        #expect(try #require(steps.first?.startTime) < steps.last!.endTime)
    }
}

struct AvailabilityResolverTests {
    private static let calendar: Calendar = {
        var cal = Calendar.current
        cal.timeZone = TimeZone(identifier: "Europe/London")!
        return cal
    }()

    private static func date(
        year: Int = 2026, month: Int = 4, day: Int = 19,
        hour: Int = 0, minute: Int = 0
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

    @Test func outsideDailyHoursProducesBlocks() {
        let availability = AvailabilityInput(
            startHour: 7, startMinute: 0,
            endHour: 21, endMinute: 0
        )

        let blocks = AvailabilityResolver.resolve(
            from: Self.date(hour: 0),
            to: Self.date(hour: 23, minute: 59),
            availability: availability,
            windows: [],
            calendar: Self.calendar
        )

        #expect(!blocks.isEmpty)
    }

    @Test func recurringWindowCreatesBlocks() {
        let availability = AvailabilityInput(
            startHour: 6, startMinute: 0,
            endHour: 22, endMinute: 0
        )

        // Day 19 April 2026 is a Sunday (weekday 1)
        let window = WindowInput(
            name: "Gym",
            isRecurring: true,
            daysOfWeek: [1],
            startHour: 18, startMinute: 0,
            endHour: 19, endMinute: 30
        )

        let blocks = AvailabilityResolver.resolve(
            from: Self.date(hour: 0),
            to: Self.date(hour: 23, minute: 59),
            availability: availability,
            windows: [window],
            calendar: Self.calendar
        )

        let gymBlock = blocks.first(where: { block in
            let startHour = Self.calendar.component(.hour, from: block.start)
            return startHour == 18
        })
        #expect(gymBlock != nil)
    }

    @Test func overlapDetectionWorks() {
        let blocks = [
            UnavailableBlock(
                start: Self.date(hour: 9),
                end: Self.date(hour: 17)
            ),
        ]

        let overlapping = AvailabilityResolver.overlaps(
            start: Self.date(hour: 10),
            end: Self.date(hour: 10, minute: 30),
            blocks: blocks
        )
        #expect(!overlapping.isEmpty)

        let clear = AvailabilityResolver.overlaps(
            start: Self.date(hour: 7),
            end: Self.date(hour: 7, minute: 30),
            blocks: blocks
        )
        #expect(clear.isEmpty)
    }
}

extension Recipe: @retroactive CustomTestStringConvertible {
    public var testDescription: String {
        name
    }
}
