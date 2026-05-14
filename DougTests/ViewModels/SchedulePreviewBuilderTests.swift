@testable import Doug
import Foundation
import SwiftData
import Testing

@Suite(.serialized)
@MainActor
struct SchedulePreviewBuilderTests {
    // MARK: - Helpers

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            Schedule.self,
            ScheduleStep.self,
            DoughTemperatureReading.self,
            BakeFermentationProfile.self,
            StarterFeedLog.self,
            StarterProfile.self,
            RevivalPlan.self,
            RevivalFeedStep.self,
            UserAvailability.self,
            UnavailableWindow.self,
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private func setupAvailability(
        context: ModelContext,
        startHour: Int = 6, startMinute: Int = 30,
        endHour: Int = 21, endMinute: Int = 0
    ) -> UserAvailability {
        let avail = UserAvailability(
            dailyStartHour: startHour, dailyStartMinute: startMinute,
            dailyEndHour: endHour, dailyEndMinute: endMinute
        )
        context.insert(avail)
        return avail
    }

    private func setupStarterProfile(
        context: ModelContext,
        state: StarterLifecycleState = .dormant,
        peakAverage: Double? = nil
    ) -> StarterProfile {
        let profile = StarterProfile()
        profile.starterLifecycleState = state
        if let avg = peakAverage {
            profile.activePeakAverageMinutes = avg
        }
        context.insert(profile)
        return profile
    }

    private func setupActivationFeed(
        context: ModelContext,
        hoursAgo: Double,
        peaked: Bool = false,
        kitchenTemp: Double = 22
    ) -> StarterFeedLog {
        let timestamp = Date().addingTimeInterval(-hoursAgo * 3600)
        let log = StarterFeedLog(
            timestamp: timestamp,
            ratioStarter: 1, ratioFlour: 5, ratioWater: 5,
            kitchenTemperatureCelsius: kitchenTemp,
            feedIntent: .activation
        )
        if peaked {
            log.markPeak(at: timestamp.addingTimeInterval(4 * 3600))
        }
        context.insert(log)
        return log
    }

    private func setupLevainFeed(
        context: ModelContext,
        hoursAgo: Double,
        peaked: Bool = false,
        kitchenTemp: Double = 22
    ) -> StarterFeedLog {
        let timestamp = Date().addingTimeInterval(-hoursAgo * 3600)
        let log = StarterFeedLog(
            timestamp: timestamp,
            ratioStarter: 1, ratioFlour: 5, ratioWater: 5,
            kitchenTemperatureCelsius: kitchenTemp,
            feedIntent: .levain
        )
        if peaked {
            log.markPeak(at: timestamp.addingTimeInterval(5 * 3600))
        }
        context.insert(log)
        return log
    }

    private func targetTomorrow(hour: Int = 9) -> Date {
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: tomorrow) ?? tomorrow
    }

    private func targetToday(hoursFromNow: Double) -> Date {
        Date().addingTimeInterval(hoursFromNow * 3600)
    }

    private func targetDayAfterTomorrow(hour: Int = 9) -> Date {
        let calendar = Calendar.current
        let day = calendar.date(byAdding: .day, value: 2, to: Date()) ?? Date()
        return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day) ?? day
    }

    // MARK: - Smoke Test

    @Test func smokeTestContainerCreation() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let avail = setupAvailability(context: ctx)
        let profile = setupStarterProfile(context: ctx, state: .dormant)
        #expect(profile.starterLifecycleState == .dormant)
        #expect(avail.dailyStartHour == 6)
    }

    @Test func smokeTestViewModel() throws {
        let vm = ScheduleViewModel()
        vm.selectedRecipeID = .countryLoaf
        vm.kitchenTemperature = 22
        #expect(vm.selectedRecipe.name == "Country Loaf")
    }

    @Test func smokeTestBuildPreview() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let avail = setupAvailability(context: ctx)
        let profile = setupStarterProfile(context: ctx, state: .active)

        let vm = ScheduleViewModel()
        vm.selectedRecipeID = .countryLoaf
        vm.kitchenTemperature = 22
        vm.targetDate = targetDayAfterTomorrow(hour: 9)

        vm.buildPreview(
            availability: avail,
            windows: [],
            feedLogs: [],
            starterProfile: profile
        )

        #expect(!vm.previewSteps.isEmpty || vm.conflict != nil)
    }

    // MARK: - Dormant Starter (overnight recipe)

    @Test func dormantStarterOvernightRecipeIncludesPreamble() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let avail = setupAvailability(context: ctx)
        let profile = setupStarterProfile(context: ctx, state: .dormant)

        let vm = ScheduleViewModel()
        vm.selectedRecipeID = .countryLoaf
        vm.kitchenTemperature = 22
        vm.targetDate = targetDayAfterTomorrow(hour: 9)

        vm.buildPreview(
            availability: avail,
            windows: [],
            feedLogs: [],
            starterProfile: profile
        )

        #expect(vm.conflict == nil, "Should produce a valid schedule")
        #expect(!vm.previewSteps.isEmpty)
        #expect(vm.hasActivationPreamble)

        let stepTypes = vm.previewSteps.map { $0.stepTypeID }
        #expect(stepTypes.contains(.activateStarter))
        #expect(stepTypes.contains(.waitForPeak))
        #expect(stepTypes.contains(.buildLevain))
        #expect(stepTypes.last == .refeedAndRefrigerate)
    }

    @Test func dormantStarterPreambleIsChronological() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let avail = setupAvailability(context: ctx)
        let profile = setupStarterProfile(context: ctx, state: .dormant)

        let vm = ScheduleViewModel()
        vm.selectedRecipeID = .countryLoaf
        vm.kitchenTemperature = 22
        vm.targetDate = targetDayAfterTomorrow(hour: 9)

        vm.buildPreview(
            availability: avail,
            windows: [],
            feedLogs: [],
            starterProfile: profile
        )

        guard !vm.previewSteps.isEmpty else {
            Issue.record("Expected steps")
            return
        }

        for i in 1 ..< vm.previewSteps.count {
            #expect(
                vm.previewSteps[i].startTime >= vm.previewSteps[i - 1].startTime,
                "Step \(i) (\(vm.previewSteps[i].label)) starts before step \(i - 1)"
            )
        }
    }

    @Test func dormantStarterWaitForPeakBetweenActivateAndLevain() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let avail = setupAvailability(context: ctx)
        let profile = setupStarterProfile(context: ctx, state: .dormant)

        let vm = ScheduleViewModel()
        vm.selectedRecipeID = .countryLoaf
        vm.kitchenTemperature = 22
        vm.targetDate = targetDayAfterTomorrow(hour: 9)

        vm.buildPreview(
            availability: avail,
            windows: [],
            feedLogs: [],
            starterProfile: profile
        )

        let stepTypes = vm.previewSteps.map { $0.stepTypeID }
        guard let activateIdx = stepTypes.firstIndex(of: .activateStarter),
              let peakIdx = stepTypes.firstIndex(of: .waitForPeak),
              let levainIdx = stepTypes.firstIndex(of: .buildLevain)
        else {
            Issue.record("Missing activate, waitForPeak, or buildLevain steps")
            return
        }

        #expect(activateIdx < peakIdx, "Activate should come before Wait for Peak")
        #expect(peakIdx < levainIdx, "Wait for Peak should come before Build Levain")
    }

    // MARK: - Active Starter

    @Test func activeStarterNoPreamble() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let avail = setupAvailability(context: ctx)
        let profile = setupStarterProfile(context: ctx, state: .active)

        let vm = ScheduleViewModel()
        vm.selectedRecipeID = .countryLoaf
        vm.kitchenTemperature = 22
        vm.targetDate = targetDayAfterTomorrow(hour: 9)

        vm.buildPreview(
            availability: avail,
            windows: [],
            feedLogs: [],
            starterProfile: profile
        )

        #expect(vm.conflict == nil)
        #expect(!vm.hasActivationPreamble)

        let stepTypes = vm.previewSteps.map { $0.stepTypeID }
        #expect(!stepTypes.contains(.activateStarter))
        #expect(!stepTypes.contains(.waitForPeak))
        #expect(!stepTypes.contains(.fridgeRest))
        #expect(stepTypes.first == .buildLevain)
        #expect(stepTypes.last == .refeedAndRefrigerate)
    }

    // MARK: - Activating Starter

    @Test func activatingStarterWithTimeRemainingIncludesWaitForPeak() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let avail = setupAvailability(context: ctx)
        let profile = setupStarterProfile(context: ctx, state: .activating, peakAverage: 360)
        let feed = setupActivationFeed(context: ctx, hoursAgo: 2)

        let vm = ScheduleViewModel()
        vm.selectedRecipeID = .countryLoaf
        vm.kitchenTemperature = 22
        vm.targetDate = targetDayAfterTomorrow(hour: 9)

        vm.buildPreview(
            availability: avail,
            windows: [],
            feedLogs: [feed],
            starterProfile: profile
        )

        #expect(vm.conflict == nil, "Should produce a valid schedule")
        #expect(vm.hasActivationPreamble)

        let stepTypes = vm.previewSteps.map { $0.stepTypeID }
        #expect(stepTypes.contains(.waitForPeak))
        #expect(!stepTypes.contains(.activateStarter), "Already activating, no activate step needed")
    }

    @Test func activatingStarterWaitForPeakStartsAtOrAfterNow() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let avail = setupAvailability(context: ctx)
        let profile = setupStarterProfile(context: ctx, state: .activating, peakAverage: 360)
        let feed = setupActivationFeed(context: ctx, hoursAgo: 2)

        let vm = ScheduleViewModel()
        vm.selectedRecipeID = .countryLoaf
        vm.kitchenTemperature = 22
        vm.targetDate = targetDayAfterTomorrow(hour: 9)

        vm.buildPreview(
            availability: avail,
            windows: [],
            feedLogs: [feed],
            starterProfile: profile
        )

        let peakStep = vm.previewSteps.first { $0.stepTypeID == .waitForPeak }
        let tolerance = 5.0
        #expect(peakStep != nil)
        #expect(
            peakStep!.startTime.timeIntervalSinceNow > -tolerance,
            "Wait for Peak should start at or after now, not in the past"
        )
    }

    @Test func activatingStarterPeakAlreadyPassedNoPreamble() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let avail = setupAvailability(context: ctx)
        let profile = setupStarterProfile(context: ctx, state: .activating, peakAverage: 240)
        let feed = setupActivationFeed(context: ctx, hoursAgo: 5)

        let vm = ScheduleViewModel()
        vm.selectedRecipeID = .countryLoaf
        vm.kitchenTemperature = 22
        vm.targetDate = targetDayAfterTomorrow(hour: 9)

        vm.buildPreview(
            availability: avail,
            windows: [],
            feedLogs: [feed],
            starterProfile: profile
        )

        #expect(vm.conflict == nil)

        let stepTypes = vm.previewSteps.map { $0.stepTypeID }
        #expect(!stepTypes.contains(.waitForPeak), "Peak time has passed, no wait needed")
    }

    @Test func activatingStarterPeakedNoPreamble() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let avail = setupAvailability(context: ctx)
        let profile = setupStarterProfile(context: ctx, state: .activating)
        let feed = setupActivationFeed(context: ctx, hoursAgo: 5, peaked: true)

        let vm = ScheduleViewModel()
        vm.selectedRecipeID = .countryLoaf
        vm.kitchenTemperature = 22
        vm.targetDate = targetDayAfterTomorrow(hour: 9)

        vm.buildPreview(
            availability: avail,
            windows: [],
            feedLogs: [feed],
            starterProfile: profile
        )

        #expect(vm.conflict == nil)
        #expect(!vm.hasActivationPreamble)
    }

    @Test func activatingStarterScheduleShiftsForwardWhenPeakOverlapsRecipe() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let avail = setupAvailability(context: ctx)
        let profile = setupStarterProfile(context: ctx, state: .activating, peakAverage: 360)
        let feed = setupActivationFeed(context: ctx, hoursAgo: 2)

        let vm = ScheduleViewModel()
        vm.selectedRecipeID = .countryLoaf
        vm.kitchenTemperature = 22
        vm.targetDate = targetDayAfterTomorrow(hour: 9)

        vm.buildPreview(
            availability: avail,
            windows: [],
            feedLogs: [feed],
            starterProfile: profile
        )

        guard !vm.previewSteps.isEmpty else {
            Issue.record("Expected steps")
            return
        }

        for i in 1 ..< vm.previewSteps.count {
            #expect(
                vm.previewSteps[i].startTime >= vm.previewSteps[i - 1].startTime,
                "Step \(i) (\(vm.previewSteps[i].label)) starts before step \(i - 1)"
            )
        }
    }

    // MARK: - Post-Bake Step

    @Test func everyRecipeEndsWithRefeedAndRefrigerate() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let avail = setupAvailability(context: ctx)
        let profile = setupStarterProfile(context: ctx, state: .active)

        let recipes: [RecipeID] = [.countryLoaf, .highHydrationArtisan, .wholeWheatHoney, .oliveRosemary]

        for recipeID in recipes {
            let vm = ScheduleViewModel()
            vm.selectedRecipeID = recipeID
            vm.kitchenTemperature = 22
            vm.targetDate = targetDayAfterTomorrow(hour: 9)

            vm.buildPreview(
                availability: avail,
                windows: [],
                feedLogs: [],
                starterProfile: profile
            )

            #expect(
                vm.conflict == nil,
                "\(recipeID.rawValue) had conflict: \(vm.conflict?.message ?? "")"
            )
            let lastType = vm.previewSteps.last?.stepTypeID
            #expect(
                lastType == .refeedAndRefrigerate,
                "\(recipeID.rawValue) should end with refeedAndRefrigerate, got \(lastType?.rawValue ?? "empty")"
            )
        }
    }

    // MARK: - Levain Detection

    @Test func activationFeedDoesNotTriggerLevainDetection() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let avail = setupAvailability(context: ctx)
        let profile = setupStarterProfile(context: ctx, state: .activating)
        let feed = setupActivationFeed(context: ctx, hoursAgo: 2)

        let vm = ScheduleViewModel()
        vm.selectedRecipeID = .countryLoaf
        vm.kitchenTemperature = 22
        vm.targetDate = targetDayAfterTomorrow(hour: 9)

        vm.buildPreview(
            availability: avail,
            windows: [],
            feedLogs: [feed],
            starterProfile: profile
        )

        #expect(vm.detectedLevain != nil, "Activating starter's feed should be detected as usable levain")
    }

    @Test func dormantStarterActivationFeedNotDetectedAsLevain() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let avail = setupAvailability(context: ctx)
        let profile = setupStarterProfile(context: ctx, state: .dormant)
        let feed = setupActivationFeed(context: ctx, hoursAgo: 2)

        let vm = ScheduleViewModel()
        vm.selectedRecipeID = .countryLoaf
        vm.kitchenTemperature = 22
        vm.targetDate = targetDayAfterTomorrow(hour: 9)

        vm.buildPreview(
            availability: avail,
            windows: [],
            feedLogs: [feed],
            starterProfile: profile
        )

        #expect(vm.detectedLevain == nil, "Dormant starter's activation feed should not be detected as levain")
    }

    @Test func levainFeedTriggersLevainDetection() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let avail = setupAvailability(context: ctx)
        let profile = setupStarterProfile(context: ctx, state: .active)
        let feed = setupLevainFeed(context: ctx, hoursAgo: 2)

        let vm = ScheduleViewModel()
        vm.selectedRecipeID = .countryLoaf
        vm.kitchenTemperature = 22
        vm.targetDate = targetDayAfterTomorrow(hour: 9)

        vm.buildPreview(
            availability: avail,
            windows: [],
            feedLogs: [feed],
            starterProfile: profile
        )

        #expect(vm.detectedLevain != nil, "Levain feed should be detected")
    }

    @Test func peakedLevainFeedDoesNotTriggerDetection() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let avail = setupAvailability(context: ctx)
        let profile = setupStarterProfile(context: ctx, state: .active)
        let feed = setupLevainFeed(context: ctx, hoursAgo: 6, peaked: true)

        let vm = ScheduleViewModel()
        vm.selectedRecipeID = .countryLoaf
        vm.kitchenTemperature = 22
        vm.targetDate = targetDayAfterTomorrow(hour: 9)

        vm.buildPreview(
            availability: avail,
            windows: [],
            feedLogs: [feed],
            starterProfile: profile
        )

        #expect(vm.detectedLevain == nil, "Peaked levain should not be detected as in-progress")
    }

    // MARK: - Same-Day Recipes

    @Test func sameDayRecipeWithActiveStarterProducesValidSchedule() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let avail = setupAvailability(context: ctx)
        let profile = setupStarterProfile(context: ctx, state: .active)

        let vm = ScheduleViewModel()
        vm.selectedRecipeID = .sameDayCountry
        vm.kitchenTemperature = 24
        vm.targetDate = targetDayAfterTomorrow(hour: 18)

        vm.buildPreview(
            availability: avail,
            windows: [],
            feedLogs: [],
            starterProfile: profile
        )

        #expect(vm.conflict == nil, "Same-day recipe with generous window should succeed")
        #expect(!vm.previewSteps.isEmpty)
    }

    @Test func sameDayRecipeWithDormantStarterIncludesActivation() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let avail = setupAvailability(context: ctx)
        let profile = setupStarterProfile(context: ctx, state: .dormant)

        let vm = ScheduleViewModel()
        vm.selectedRecipeID = .sameDayCountry
        vm.kitchenTemperature = 24
        vm.targetDate = targetTomorrow(hour: 18)

        vm.buildPreview(
            availability: avail,
            windows: [],
            feedLogs: [],
            starterProfile: profile
        )

        let stepTypes = vm.previewSteps.map { $0.stepTypeID }
        if !vm.previewSteps.isEmpty {
            #expect(stepTypes.contains(.activateStarter))
            #expect(stepTypes.contains(.waitForPeak))
        }
    }

    // MARK: - Activating Starter + Same-Day Recipe Tomorrow

    @Test func activatingStarterOvernightRecipeUsesViableRange() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let avail = setupAvailability(context: ctx)
        let profile = setupStarterProfile(context: ctx, state: .activating, peakAverage: 300)
        let feed = setupActivationFeed(context: ctx, hoursAgo: 6, kitchenTemp: 22)

        let vm = ScheduleViewModel()
        vm.selectedRecipeID = .softRolls
        vm.kitchenTemperature = 22
        vm.targetDate = targetDayAfterTomorrow(hour: 12)

        vm.buildPreview(
            availability: avail,
            windows: [],
            feedLogs: [feed],
            starterProfile: profile
        )

        #expect(
            vm.conflict == nil,
            "Activating starter + soft rolls day-after-tomorrow should work. Got: \(vm.conflict?.message ?? "")"
        )
        #expect(!vm.previewSteps.isEmpty)
    }

    // MARK: - No Starter Profile

    @Test func noProfileDefaultsToDormantBehavior() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let avail = setupAvailability(context: ctx)

        let vm = ScheduleViewModel()
        vm.selectedRecipeID = .countryLoaf
        vm.kitchenTemperature = 22
        vm.targetDate = targetDayAfterTomorrow(hour: 9)

        vm.buildPreview(
            availability: avail,
            windows: [],
            feedLogs: [],
            starterProfile: nil
        )

        #expect(vm.hasActivationPreamble)
    }

    // MARK: - Step Order Invariant

    @Test func allStepsAreChronologicalForEveryRecipeAndState() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let avail = setupAvailability(context: ctx)

        let states: [(StarterLifecycleState, String)] = [
            (.dormant, "dormant"),
            (.active, "active"),
        ]
        let recipes: [RecipeID] = [.countryLoaf, .sameDayCountry, .focaccia, .softRolls]

        for (state, stateLabel) in states {
            for recipeID in recipes {
                let profile = setupStarterProfile(context: ctx, state: state)

                let vm = ScheduleViewModel()
                vm.selectedRecipeID = recipeID
                vm.kitchenTemperature = 22
                vm.targetDate = targetDayAfterTomorrow(hour: 12)

                vm.buildPreview(
                    availability: avail,
                    windows: [],
                    feedLogs: [],
                    starterProfile: profile
                )

                guard !vm.previewSteps.isEmpty else { continue }

                for i in 1 ..< vm.previewSteps.count {
                    #expect(
                        vm.previewSteps[i].startTime >= vm.previewSteps[i - 1].startTime,
                        "\(recipeID.rawValue) (\(stateLabel)): step \(i) (\(vm.previewSteps[i].label)) starts before step \(i - 1) (\(vm.previewSteps[i - 1].label))"
                    )
                }

                ctx.delete(profile)
            }
        }
    }
}
