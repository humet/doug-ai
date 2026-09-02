@testable import Doug
import Foundation
import Testing
import UserNotifications

/// Pins the behavior of every (category, action) pair a notification response
/// can deliver — the full tap/action matrix from the notification UX audit.
@MainActor
struct NotificationRoutingTests {
    private typealias Routed = NotificationActionHandler.RoutedAction
    private typealias Category = NotificationService.Category
    private typealias Action = NotificationService.Action

    private func route(
        _ category: String,
        _ action: String,
        stepTypeID: String? = nil,
        sequenceIndex: Int? = nil
    ) -> Routed {
        NotificationActionHandler.route(
            categoryIdentifier: category,
            actionIdentifier: action,
            stepTypeID: stepTypeID,
            sequenceIndex: sequenceIndex
        )
    }

    // MARK: - Starter feed

    @Test func starterFeedTapOpensStarterTab() {
        #expect(route(Category.starterFeed, UNNotificationDefaultActionIdentifier) == .openStarterTab)
    }

    @Test func starterFeedLogFeedOpensLogSheet() {
        #expect(route(Category.starterFeed, Action.logFeed) == .openStarterLogFeed)
    }

    @Test func starterFeedSnoozeRedeliversInAnHour() {
        #expect(route(Category.starterFeed, Action.snoozeFeed) == .snoozeSame(minutes: 60))
    }

    // MARK: - Revival mix

    @Test func revivalMixTapOpensStarterTab() {
        #expect(route(Category.revivalMix, UNNotificationDefaultActionIdentifier) == .openStarterTab)
    }

    @Test func revivalMixSnoozeRedeliversInThirtyMinutes() {
        #expect(route(Category.revivalMix, Action.snoozeStep) == .snoozeSame(minutes: 30))
    }

    @Test func revivalMixNeverLogsAGenericFeed() {
        // The old shared category made "Log Feed" insert a generic feed log for
        // a revival reminder — the revival category must not route there.
        #expect(route(Category.revivalMix, Action.logFeed) == Routed.none)
    }

    // MARK: - Fold steps

    @Test func foldTapOpensTemperatureEntry() {
        let routed = route(
            Category.foldStep, UNNotificationDefaultActionIdentifier,
            stepTypeID: StepTypeID.stretchAndFold.rawValue, sequenceIndex: 1
        )
        #expect(routed == .foldEntry(stepTypeID: StepTypeID.stretchAndFold.rawValue, sequenceIndex: 1))
    }

    @Test func foldTapWithoutStepInfoFocusesSchedule() {
        #expect(route(Category.foldStep, UNNotificationDefaultActionIdentifier) == .focusScheduleTab)
    }

    @Test func foldSnoozeRedeliversNotMutatesSchedule() {
        #expect(route(
            Category.foldStep, Action.snoozeStep,
            stepTypeID: StepTypeID.stretchAndFold.rawValue, sequenceIndex: 1
        ) == .snoozeSame(minutes: 30))
    }

    // MARK: - Hands-on steps and preheat

    @Test func handsOnTapOpensStepDetail() {
        let routed = route(
            Category.handsOnStep, UNNotificationDefaultActionIdentifier,
            stepTypeID: StepTypeID.shape.rawValue, sequenceIndex: 4
        )
        #expect(routed == .stepDetail(stepTypeID: StepTypeID.shape.rawValue, sequenceIndex: 4))
    }

    @Test func preheatTapOpensStepDetailLikeOtherSteps() {
        let routed = route(
            Category.coldRetardEnd, UNNotificationDefaultActionIdentifier,
            stepTypeID: StepTypeID.preheat.rawValue, sequenceIndex: 6
        )
        #expect(routed == .stepDetail(stepTypeID: StepTypeID.preheat.rawValue, sequenceIndex: 6))
    }

    @Test func preheatTapWithoutStepInfoFocusesSchedule() {
        #expect(route(Category.coldRetardEnd, UNNotificationDefaultActionIdentifier) == .focusScheduleTab)
    }

    @Test func preheatSnoozeRedelivers() {
        #expect(route(Category.coldRetardEnd, Action.snoozeStep) == .snoozeSame(minutes: 30))
    }

    // MARK: - Bake phases

    @Test func bakePhaseDoneMarksSubStepDone() {
        let routed = route(
            Category.bakePhase, Action.markBakePhaseDone,
            stepTypeID: StepTypeID.bakeCovered.rawValue, sequenceIndex: 0
        )
        #expect(routed == .bakeDone(stepTypeID: StepTypeID.bakeCovered.rawValue, sequenceIndex: 0))
    }

    @Test func bakePhaseTapOpensStepDetail() {
        let routed = route(
            Category.bakePhase, UNNotificationDefaultActionIdentifier,
            stepTypeID: StepTypeID.bakeUncovered.rawValue, sequenceIndex: 1
        )
        #expect(routed == .stepDetail(stepTypeID: StepTypeID.bakeUncovered.rawValue, sequenceIndex: 1))
    }

    @Test func bakePhaseSnoozeIsGone() {
        // Bake phases are on a physical timeline; the snooze action is no
        // longer registered, and even a stale button must do nothing.
        #expect(route(Category.bakePhase, Action.snoozeStep) == Routed.none)
    }

    // MARK: - Unknown input

    @Test func unknownCategoryDoesNothing() {
        #expect(route("SOMETHING_ELSE", UNNotificationDefaultActionIdentifier) == Routed.none)
    }

    @Test func dismissActionDoesNothing() {
        #expect(route(Category.handsOnStep, UNNotificationDismissActionIdentifier) == Routed.none)
    }
}
