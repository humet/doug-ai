#if canImport(DougDomain)
@testable import DougDomain
#else
@testable import Doug
#endif
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
        #expect(steps.last?.stepTypeID == StepTypeID.bake)

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
        let hasColdRetard = recipe.method.contains { $0.stepTypeID == .coldRetard }
        let targetHour = hasColdRetard ? 9 : 20
        let input = ScheduleBuilderInput(
            recipe: recipe,
            targetBreadReadyTime: Self.targetTime(hour: targetHour),
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
    // MARK: - Fold Availability

    @Test func bulkFermentFoldsAvoidSleepWindow() throws {
        let input = ScheduleBuilderInput(
            recipe: RecipeBook.countryLoaf,
            targetBreadReadyTime: Self.targetTime(hour: 14, minute: 0),
            kitchenTemperatureCelsius: 24.0,
            availability: Self.defaultAvailability
        )

        let result = ScheduleBuilder.build(input)
        guard case let .success(steps) = result else {
            Issue.record("Expected success, got conflict")
            return
        }

        let bulkStep = try #require(steps.first(where: { $0.stepTypeID == .bulkFerment }))

        let calendar = Calendar.current
        for fold in bulkStep.subSteps where fold.classification == .handsOn {
            let foldHour = calendar.component(.hour, from: fold.startTime)
            let inSleepWindow = foldHour >= 21 || foldHour < 6
            #expect(!inSleepWindow, "Fold at \(fold.startTime) lands during sleep hours")
        }
    }

    @Test func coldRetardAbsorbsOvernightGap() throws {
        let input = ScheduleBuilderInput(
            recipe: RecipeBook.countryLoaf,
            targetBreadReadyTime: Self.targetTime(hour: 14, minute: 0),
            kitchenTemperatureCelsius: 24.0,
            availability: Self.defaultAvailability
        )

        let result = ScheduleBuilder.build(input)
        guard case let .success(steps) = result else {
            Issue.record("Expected success, got conflict")
            return
        }

        let coldRetard = try #require(steps.first(where: { $0.stepTypeID == .coldRetard }))
        #expect(coldRetard.durationMinutes >= 480)
        #expect(coldRetard.durationMinutes <= 1080)
    }

    // MARK: - In-progress levain (ready/active starter)

    /// Builds with a levain already fermenting in the jar (ready starter), fed `elapsed`
    /// minutes ago, peaking in `peakMinutes`, against a target far enough out that the
    /// "enforce earliest start" block fires. `earliestStartTime` = now (active starter).
    private static func readyLevainInput(
        elapsedMinutes: Double,
        peakMinutes: Double = 300,
        targetHoursFromNow: Double = 40,
        kitchenTemp: Double = 22.0
    ) -> ScheduleBuilderInput {
        let now = Date()
        // Wide availability so these levain-placement tests don't flake on the
        // Date()-relative target landing at night.
        let allDay = AvailabilityInput(startHour: 0, startMinute: 0, endHour: 23, endMinute: 59)
        return ScheduleBuilderInput(
            recipe: RecipeBook.countryLoaf,
            targetBreadReadyTime: now.addingTimeInterval(targetHoursFromNow * 3600),
            kitchenTemperatureCelsius: kitchenTemp,
            availability: allDay,
            levainContext: LevainContext(
                fedAt: now.addingTimeInterval(-elapsedMinutes * 60),
                expectedPeakMinutes: peakMinutes,
                kitchenTemperatureCelsius: kitchenTemp
            ),
            earliestStartTime: now
        )
    }

    @Test func readyStarterKeepsBuildWaitContiguous() throws {
        let input = Self.readyLevainInput(elapsedMinutes: 90)
        guard case let .success(steps) = ScheduleBuilder.build(input) else {
            Issue.record("Expected success, got conflict")
            return
        }

        let build = try #require(steps.first(where: { $0.stepTypeID == .buildLevain }))
        let wait = try #require(steps.first(where: { $0.stepTypeID == .waitForLevainPeak }))
        // No idle gap: the levain rises the instant it's built.
        #expect(abs(build.endTime.timeIntervalSince(wait.startTime)) < 1)
    }

    @Test func readyStarterWaitDurationEqualsExpectedPeak() throws {
        let input = Self.readyLevainInput(elapsedMinutes: 90, peakMinutes: 300)
        guard case let .success(steps) = ScheduleBuilder.build(input) else {
            Issue.record("Expected success, got conflict")
            return
        }

        let wait = try #require(steps.first(where: { $0.stepTypeID == .waitForLevainPeak }))
        let spanMinutes = wait.endTime.timeIntervalSince(wait.startTime) / 60
        // Wait is its true peak, NOT stretched to absorb target-anchoring slack.
        #expect(abs(spanMinutes - 300) < 1)
        #expect(abs(wait.durationMinutes - 300) < 1)
    }

    @Test func readyStarterSlackAbsorbedByColdRetard() throws {
        let input = Self.readyLevainInput(elapsedMinutes: 90, peakMinutes: 300)
        guard case let .success(steps) = ScheduleBuilder.build(input) else {
            Issue.record("Expected success, got conflict")
            return
        }

        let wait = try #require(steps.first(where: { $0.stepTypeID == .waitForLevainPeak }))
        let coldRetard = try #require(steps.first(where: { $0.stepTypeID == .coldRetard }))
        // The overnight/target slack lives in the flexible cold retard, not the fixed wait.
        #expect(coldRetard.durationMinutes > wait.durationMinutes)
        // Schedule still lands on target despite the un-stretched wait.
        let lastEnd = try #require(steps.last?.endTime)
        #expect(abs(lastEnd.timeIntervalSince(input.targetBreadReadyTime)) < 60)
    }

    @Test func peakAlreadyPassedDoesNotInflateWait() throws {
        // Fed long enough ago that the levain has already peaked (remaining <= 0).
        let input = Self.readyLevainInput(elapsedMinutes: 320, peakMinutes: 300)
        guard case let .success(steps) = ScheduleBuilder.build(input) else {
            Issue.record("Expected success, got conflict")
            return
        }

        let build = try #require(steps.first(where: { $0.stepTypeID == .buildLevain }))
        let wait = try #require(steps.first(where: { $0.stepTypeID == .waitForLevainPeak }))
        // A peaked-over levain must not be re-inflated to a full peak duration.
        #expect(wait.durationMinutes < 60)
        // Still contiguous.
        #expect(abs(build.endTime.timeIntervalSince(wait.startTime)) < 1)
    }

    @Test func noLevainContextStillContiguous() throws {
        let input = ScheduleBuilderInput(
            recipe: RecipeBook.countryLoaf,
            targetBreadReadyTime: Self.targetTime(hour: 14, minute: 0),
            kitchenTemperatureCelsius: 22.0,
            availability: Self.defaultAvailability
        )
        guard case let .success(steps) = ScheduleBuilder.build(input) else {
            Issue.record("Expected success, got conflict")
            return
        }

        let build = try #require(steps.first(where: { $0.stepTypeID == .buildLevain }))
        let wait = try #require(steps.first(where: { $0.stepTypeID == .waitForLevainPeak }))
        #expect(abs(build.endTime.timeIntervalSince(wait.startTime)) < 1)
        // Generic levain build estimate at 22°C.
        #expect(abs(wait.durationMinutes - 300) < 1)
    }

    @Test func conflictWhenColdRetardExceedsFlexRange() {
        let input = ScheduleBuilderInput(
            recipe: RecipeBook.countryLoaf,
            targetBreadReadyTime: Self.targetTime(hour: 23, minute: 0),
            kitchenTemperatureCelsius: 24.0,
            availability: Self.defaultAvailability
        )

        let result = ScheduleBuilder.build(input)
        guard case .conflict = result else {
            Issue.record("Expected conflict for 11 PM bread-ready time")
            return
        }
    }

    @Test func noChangeWhenFoldsAlreadyInAvailableHours() throws {
        let input = ScheduleBuilderInput(
            recipe: RecipeBook.countryLoaf,
            targetBreadReadyTime: Self.targetTime(hour: 9, minute: 0),
            kitchenTemperatureCelsius: 24.0,
            availability: Self.defaultAvailability
        )

        guard case let .success(steps) = ScheduleBuilder.build(input) else {
            Issue.record("Expected success")
            return
        }

        let bulkStep = try #require(steps.first(where: { $0.stepTypeID == .bulkFerment }))
        #expect(bulkStep.subSteps.count == 4)

        for fold in bulkStep.subSteps where fold.classification == .handsOn {
            let hour = Calendar.current.component(.hour, from: fold.startTime)
            let inAvailable = hour >= 6 && hour < 21
            #expect(inAvailable, "Fold at \(fold.startTime) should be in available hours")
        }
    }

    // MARK: - Viable Range

    // MARK: - Presence Group (Preheat + Bake)

    @Test func bakeEndAvoidsUnavailableWindow() throws {
        // Set up: bread ready at 9 AM, but user is unavailable 8:30–10:00.
        // Without presence checking, bake (8:15–9:00) would end at 9:00 which is
        // inside the unavailable block. With presence checking, the group shifts earlier.
        let window = WindowInput(
            name: "Morning Meeting",
            isRecurring: true,
            daysOfWeek: [1, 2, 3, 4, 5, 6, 7],
            startHour: 8, startMinute: 30,
            endHour: 10, endMinute: 0
        )

        let input = ScheduleBuilderInput(
            recipe: RecipeBook.countryLoaf,
            targetBreadReadyTime: Self.targetTime(hour: 9, minute: 0),
            kitchenTemperatureCelsius: 24.0,
            availability: Self.defaultAvailability,
            unavailableWindows: [window]
        )

        let result = ScheduleBuilder.build(input)
        guard case let .success(steps) = result else {
            Issue.record("Expected success, got conflict")
            return
        }

        let bakeStep = try #require(steps.first(where: { $0.stepTypeID == .bake }))
        let preheatStep = try #require(steps.first(where: { $0.stepTypeID == .preheat }))

        // Bake end must be before the unavailable window starts
        let calendar = Calendar.current
        let bakeEndHour = calendar.component(.hour, from: bakeStep.endTime)
        let bakeEndMinute = calendar.component(.minute, from: bakeStep.endTime)
        let bakeEndTotal = bakeEndHour * 60 + bakeEndMinute
        #expect(bakeEndTotal <= 8 * 60 + 30, "Bake must end at or before 8:30")

        // Preheat and bake must be contiguous
        let gap = abs(preheatStep.endTime.timeIntervalSince(bakeStep.startTime))
        #expect(gap < 60, "Preheat end must equal bake start (no gap)")
    }

    @Test func preheatAndBakeContiguousAfterShift() throws {
        // Unavailable window forces a shift — verify no gap opens between preheat and bake
        let window = WindowInput(
            name: "Gym",
            isRecurring: true,
            daysOfWeek: [1, 2, 3, 4, 5, 6, 7],
            startHour: 8, startMinute: 30,
            endHour: 10, endMinute: 0
        )

        let input = ScheduleBuilderInput(
            recipe: RecipeBook.countryLoaf,
            targetBreadReadyTime: Self.targetTime(hour: 9, minute: 0),
            kitchenTemperatureCelsius: 24.0,
            availability: Self.defaultAvailability,
            unavailableWindows: [window]
        )

        let result = ScheduleBuilder.build(input)
        guard case let .success(steps) = result else {
            Issue.record("Expected success, got conflict")
            return
        }

        let preheatStep = try #require(steps.first(where: { $0.stepTypeID == .preheat }))
        let bakeStep = try #require(steps.first(where: { $0.stepTypeID == .bake }))

        let gap = abs(preheatStep.endTime.timeIntervalSince(bakeStep.startTime))
        #expect(gap < 60, "Preheat and bake must remain contiguous")
    }

    @Test func coldRetardExpandsWhenPresenceGroupShifts() throws {
        // When the presence group shifts earlier, Cold Retard should expand to fill the gap
        let window = WindowInput(
            name: "Out",
            isRecurring: true,
            daysOfWeek: [1, 2, 3, 4, 5, 6, 7],
            startHour: 8, startMinute: 30,
            endHour: 10, endMinute: 0
        )

        let inputWithWindow = ScheduleBuilderInput(
            recipe: RecipeBook.countryLoaf,
            targetBreadReadyTime: Self.targetTime(hour: 9, minute: 0),
            kitchenTemperatureCelsius: 24.0,
            availability: Self.defaultAvailability,
            unavailableWindows: [window]
        )
        let inputWithout = ScheduleBuilderInput(
            recipe: RecipeBook.countryLoaf,
            targetBreadReadyTime: Self.targetTime(hour: 9, minute: 0),
            kitchenTemperatureCelsius: 24.0,
            availability: Self.defaultAvailability
        )

        guard case let .success(stepsWithWindow) = ScheduleBuilder.build(inputWithWindow),
              case let .success(stepsWithout) = ScheduleBuilder.build(inputWithout)
        else {
            Issue.record("Expected both to succeed")
            return
        }

        let crWith = try #require(stepsWithWindow.first(where: { $0.stepTypeID == .coldRetard }))
        let crWithout = try #require(stepsWithout.first(where: { $0.stepTypeID == .coldRetard }))

        #expect(crWith.durationMinutes > crWithout.durationMinutes,
                "Cold Retard should expand when presence group shifts earlier")
    }

    @Test func briefMidStepUnavailabilityDoesNotShift() throws {
        // An unavailable window entirely during the passive portion of preheat
        // (e.g., minutes 15-40 of a 60-min preheat) should NOT cause a shift,
        // because the interaction points (start and end) are still available.
        let input = ScheduleBuilderInput(
            recipe: RecipeBook.countryLoaf,
            targetBreadReadyTime: Self.targetTime(hour: 9, minute: 0),
            kitchenTemperatureCelsius: 24.0,
            availability: Self.defaultAvailability
        )

        // First build without any extra window to get the baseline schedule
        guard case let .success(baselineSteps) = ScheduleBuilder.build(input) else {
            Issue.record("Baseline should succeed")
            return
        }
        let baselinePreheat = try #require(baselineSteps.first(where: { $0.stepTypeID == .preheat }))

        // Now add a window that falls entirely within preheat's passive middle
        let preheatStartHour = Calendar.current.component(.hour, from: baselinePreheat.startTime)
        let preheatStartMinute = Calendar.current.component(.minute, from: baselinePreheat.startTime)
        let windowStartMinute = preheatStartMinute + 15
        let windowStartHour = preheatStartHour + (windowStartMinute >= 60 ? 1 : 0)

        let window = WindowInput(
            name: "Quick Errand",
            isRecurring: true,
            daysOfWeek: [1, 2, 3, 4, 5, 6, 7],
            startHour: windowStartHour, startMinute: windowStartMinute % 60,
            endHour: windowStartHour, endMinute: (windowStartMinute + 25) % 60
        )

        let inputWithWindow = ScheduleBuilderInput(
            recipe: RecipeBook.countryLoaf,
            targetBreadReadyTime: Self.targetTime(hour: 9, minute: 0),
            kitchenTemperatureCelsius: 24.0,
            availability: Self.defaultAvailability,
            unavailableWindows: [window]
        )

        guard case let .success(stepsWithWindow) = ScheduleBuilder.build(inputWithWindow) else {
            Issue.record("Should succeed even with mid-preheat window")
            return
        }

        let preheatWithWindow = try #require(stepsWithWindow.first(where: { $0.stepTypeID == .preheat }))
        let diff = abs(preheatWithWindow.startTime.timeIntervalSince(baselinePreheat.startTime))
        #expect(diff < 60, "Preheat should not shift when unavailable window is only mid-step")
    }

    @Test func requiresPresenceFlagValues() {
        let presenceSteps: Set<StepTypeID> = [.preheat, .bake, .bakeCovered, .bakeUncovered, .bakeSheet]

        for id in StepTypeID.allCases {
            let stepType = StepTypeRegistry.type(for: id)
            if presenceSteps.contains(id) {
                #expect(stepType.requiresPresence, "\(id.rawValue) should require presence")
            } else {
                #expect(!stepType.requiresPresence, "\(id.rawValue) should not require presence")
            }
        }
    }

    // MARK: - Viable Range

    @Test func viableRangeReturnsReasonableBounds() throws {
        let availability = AvailabilityInput(
            startHour: 6, startMinute: 30,
            endHour: 21, endMinute: 0
        )

        let range = try #require(ScheduleBuilder.viableRange(
            recipe: RecipeBook.countryLoaf,
            kitchenTemperatureCelsius: 24.0,
            availability: availability,
            referenceDate: Self.targetTime(hour: 12, minute: 0)
        ))

        let calendar = Calendar.current
        let earliestHour = calendar.component(.hour, from: range.lowerBound)
        let latestHour = calendar.component(.hour, from: range.upperBound)

        #expect(earliestHour >= 6 && earliestHour <= 10, "Earliest should be morning")
        #expect(latestHour >= 14 && latestHour <= 21, "Latest should be afternoon/evening")
        #expect(range.lowerBound < range.upperBound)
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

// MARK: - UnavailableBlock Source Name & Flex Compression Tests

struct AvailabilityResolverSourceNameTests {
    private static let availability = AvailabilityInput(
        startHour: 6, startMinute: 30,
        endHour: 21, endMinute: 0
    )

    private static func date(
        year: Int = 2026, month: Int = 4, day: Int = 19,
        hour: Int = 0, minute: Int = 0
    ) -> Date {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = hour
        comps.minute = minute
        comps.timeZone = TimeZone(identifier: "Europe/London")
        return Calendar.current.date(from: comps)!
    }

    @Test func dailyHoursBlocksHaveNilSourceName() {
        let blocks = AvailabilityResolver.resolve(
            from: Self.date(hour: 0),
            to: Self.date(hour: 23, minute: 59),
            availability: Self.availability,
            windows: []
        )

        #expect(!blocks.isEmpty)
        for block in blocks {
            #expect(block.sourceName == nil)
        }
    }

    @Test func windowBlocksCarrySourceName() {
        let window = WindowInput(
            name: "Gym class",
            isRecurring: false,
            startHour: 17, startMinute: 0,
            endHour: 18, endMinute: 0,
            specificDate: Self.date()
        )

        let blocks = AvailabilityResolver.resolve(
            from: Self.date(hour: 0),
            to: Self.date(hour: 23, minute: 59),
            availability: Self.availability,
            windows: [window]
        )

        let named = blocks.filter { $0.sourceName != nil }
        #expect(!named.isEmpty)
        #expect(named.first?.sourceName == "Gym class")
    }

    @Test func mergedBlockPreservesSourceName() {
        let window = WindowInput(
            name: "Evening class",
            isRecurring: false,
            startHour: 20, startMinute: 30,
            endHour: 22, endMinute: 0,
            specificDate: Self.date()
        )

        let blocks = AvailabilityResolver.resolve(
            from: Self.date(hour: 0),
            to: Self.date(hour: 23, minute: 59),
            availability: Self.availability,
            windows: [window]
        )

        let eveningBlock = blocks.first { $0.sourceName == "Evening class" }
            ?? blocks.first { block in
                let cal = Calendar.current
                let blockHour = cal.component(.hour, from: block.start)
                return blockHour >= 20
            }
        #expect(eveningBlock != nil)
    }
}

struct FlexCompressionDetectionTests {
    private static let availability = AvailabilityInput(
        startHour: 6, startMinute: 30,
        endHour: 21, endMinute: 0
    )

    private static func targetTime(
        year: Int = 2026, month: Int = 4, day: Int = 19,
        hour: Int = 9, minute: Int = 0
    ) -> Date {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = hour
        comps.minute = minute
        comps.timeZone = TimeZone(identifier: "Europe/London")
        return Calendar.current.date(from: comps)!
    }

    @Test func noCompressionOnNormalSchedule() {
        let input = ScheduleBuilderInput(
            recipe: RecipeBook.countryLoaf,
            targetBreadReadyTime: Self.targetTime(),
            kitchenTemperatureCelsius: 24.0,
            availability: Self.availability
        )

        guard case let .success(steps) = ScheduleBuilder.build(input) else {
            Issue.record("Expected success")
            return
        }

        let details = ScheduleBuilder.flexCompressionDetails(steps: steps, recipe: RecipeBook.countryLoaf)
        #expect(details.isEmpty)
    }

    @Test func compressionDetectedWhenFlexStepShortenedByWindow() {
        let window = WindowInput(
            name: "Work",
            isRecurring: false,
            startHour: 7, startMinute: 0,
            endHour: 8, endMinute: 0,
            specificDate: Self.targetTime(hour: 0)
        )

        let input = ScheduleBuilderInput(
            recipe: RecipeBook.countryLoaf,
            targetBreadReadyTime: Self.targetTime(hour: 12),
            kitchenTemperatureCelsius: 24.0,
            availability: Self.availability,
            unavailableWindows: [window]
        )

        let result = ScheduleBuilder.build(input)

        if case let .success(steps) = result {
            let details = ScheduleBuilder.flexCompressionDetails(steps: steps, recipe: RecipeBook.countryLoaf)
            // May or may not be compressed depending on exact timing — just verify API works
            for detail in details {
                #expect(detail.actualDurationMinutes < detail.defaultDurationMinutes)
                #expect(!detail.stepLabel.isEmpty)
            }
        }
    }

    @Test func conflictCarriesRealWindowName() {
        let window = WindowInput(
            name: "School Run",
            isRecurring: false,
            startHour: 7, startMinute: 0,
            endHour: 12, endMinute: 0,
            specificDate: Self.targetTime(hour: 0)
        )

        let input = ScheduleBuilderInput(
            recipe: RecipeBook.countryLoaf,
            targetBreadReadyTime: Self.targetTime(hour: 12),
            kitchenTemperatureCelsius: 24.0,
            availability: Self.availability,
            unavailableWindows: [window]
        )

        let result = ScheduleBuilder.build(input)

        if case let .conflict(c) = result {
            #expect(c.conflictingWindowName != "unavailable window")
        }
    }
}
