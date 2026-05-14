@testable import Doug
import Foundation
import SwiftData
import Testing

@MainActor
struct ScheduleViewModelApplyOptionTests {
    @Test func applyingShiftedTargetOptionResolvesConflictAndRebuildsPreview() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: UserAvailability.self, UnavailableWindow.self,
            configurations: config
        )
        let ctx = container.mainContext

        let availability = UserAvailability(
            dailyStartHour: 6, dailyStartMinute: 0,
            dailyEndHour: 22, dailyEndMinute: 0
        )
        ctx.insert(availability)

        // Two non-adjacent Saturday blocks sandwich the shape step so
        // ScheduleBuilder's single-shot local resolution fails: the shape
        // can't fit in its tentative evening slot AND can't shift earlier
        // into the narrow 15-minute gap between the blocks.
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let nextSaturday = try #require(
            cal.nextDate(after: today, matching: DateComponents(weekday: 7), matchingPolicy: .nextTime)
        )
        let blockEarly = UnavailableWindow(
            name: "Saturday afternoon errand",
            isRecurring: false,
            daysOfWeek: [],
            startHour: 17, startMinute: 0,
            endHour: 17, endMinute: 45,
            specificDate: nextSaturday
        )
        let blockLate = UnavailableWindow(
            name: "Saturday evening out",
            isRecurring: false,
            daysOfWeek: [],
            startHour: 18, startMinute: 0,
            endHour: 22, endMinute: 0,
            specificDate: nextSaturday
        )
        ctx.insert(blockEarly)
        ctx.insert(blockLate)

        // Target: Sunday 09:00 → shape lands Saturday evening
        // in blockLate; resolution shifts it to just-before blockLate where
        // it overlaps blockEarly → .conflict.
        let sunday9am = try #require(
            cal.date(byAdding: .day, value: 1, to: cal.date(bySettingHour: 9, minute: 0, second: 0, of: nextSaturday)!)
        )

        let viewModel = ScheduleViewModel()
        viewModel.selectedRecipeID = .countryLoaf
        viewModel.kitchenTemperature = 24.0
        viewModel.targetDate = sunday9am

        let windows = [blockEarly, blockLate]
        viewModel.buildPreview(availability: availability, windows: windows)
        #expect(viewModel.conflict != nil)
        #expect(viewModel.previewSteps.isEmpty)

        // Apply +24h shift: target moves to Monday 09:00 so shape lands on
        // Sunday evening (which has no blocks) → rebuild succeeds.
        let shiftMinutes: Double = 24 * 60
        let option = ConflictOption(
            summary: "Push bake 24h later",
            explanation: "Moves hands-on work off the blocked Saturday.",
            targetTimeShiftMinutes: shiftMinutes
        )
        viewModel.apply(option: option, availability: availability, windows: windows)

        #expect(!viewModel.previewSteps.isEmpty)
        #expect(viewModel.conflict == nil)
        #expect(viewModel.showConflictSheet == false)
        #expect(viewModel.targetDate == sunday9am.addingTimeInterval(shiftMinutes * 60))
    }
}
