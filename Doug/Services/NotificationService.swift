import Foundation
import UserNotifications

@MainActor
final class NotificationService {
    static let shared = NotificationService()

    private let center = UNUserNotificationCenter.current()

    /// Category identifiers for actionable notifications.
    enum Category {
        static let foldStep = "FOLD_STEP"
        static let handsOnStep = "HANDS_ON_STEP"
        static let coldRetardEnd = "COLD_RETARD_END"
        static let starterFeed = "STARTER_FEED"
    }

    /// Action identifiers for interactive notifications.
    enum Action {
        static let logFeed = "LOG_FEED"
        static let snoozeFeed = "SNOOZE_FEED_1H"
        static let snoozeStep = "SNOOZE_STEP_30M"
    }

    /// Stable identifier so feed reminders can be rescheduled or cancelled cleanly.
    private static let starterFeedIdentifier = "starter-feed-reminder"

    // MARK: - Authorization

    func requestAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    /// Registers all notification categories and their actions. Call once at app launch.
    func registerCategories() {
        let logFeedAction = UNNotificationAction(
            identifier: Action.logFeed,
            title: "Log Feed",
            options: [.foreground]
        )
        let snoozeFeedAction = UNNotificationAction(
            identifier: Action.snoozeFeed,
            title: "Snooze 1h",
            options: []
        )
        let starterFeedCategory = UNNotificationCategory(
            identifier: Category.starterFeed,
            actions: [logFeedAction, snoozeFeedAction],
            intentIdentifiers: [],
            options: []
        )

        let snoozeStepAction = UNNotificationAction(
            identifier: Action.snoozeStep,
            title: "Snooze 30m",
            options: []
        )
        let handsOnStepCategory = UNNotificationCategory(
            identifier: Category.handsOnStep,
            actions: [snoozeStepAction],
            intentIdentifiers: [],
            options: []
        )
        let foldStepCategory = UNNotificationCategory(
            identifier: Category.foldStep,
            actions: [snoozeStepAction],
            intentIdentifiers: [],
            options: []
        )

        center.setNotificationCategories([
            starterFeedCategory,
            handsOnStepCategory,
            foldStepCategory,
        ])
    }

    // MARK: - Schedule Notifications

    /// Schedules notifications for all hands-on steps in a schedule.
    /// Fires 5 minutes before each step.
    func scheduleNotifications(for steps: [ScheduleStep]) async {
        let authorized = await requestAuthorization()
        guard authorized else { return }

        for step in steps {
            let stepType = step.stepType

            // Only notify for hands-on steps + preheat + cold retard end
            guard stepType.classification == .handsOn
                || step.stepTypeID == StepStatus.upcoming.rawValue // won't match, handled below
                || stepType.id == .preheat
            else {
                continue
            }

            await scheduleStepNotification(step: step)

            // Also schedule sub-steps (folds)
            for subStep in step.subSteps {
                await scheduleStepNotification(step: subStep)
            }
        }
    }

    /// Schedules a single step notification, firing 5 minutes before the step.
    private func scheduleStepNotification(step: ScheduleStep) async {
        let stepType = step.stepType
        let notifTime = step.computedStartTime.addingTimeInterval(-5 * 60)

        guard notifTime > Date() else { return }

        let content = UNMutableNotificationContent()
        content.title = stepType.label
        content.body = stepType.notificationText
        content.sound = .default

        if stepType.requiresTempReading {
            content.categoryIdentifier = Category.foldStep
        } else if stepType.id == .preheat {
            content.categoryIdentifier = Category.coldRetardEnd
        } else {
            content.categoryIdentifier = Category.handsOnStep
        }

        // Store step info for deep-linking
        content.userInfo = [
            "stepTypeID": step.stepTypeID,
            "sequenceIndex": step.sequenceIndex,
        ]

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: max(notifTime.timeIntervalSinceNow, 1),
            repeats: false
        )

        let identifier = "step-\(step.stepTypeID)-\(step.sequenceIndex)"
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: trigger
        )

        do {
            try await center.add(request)
            // Store identifier back on the step for later cancellation
            step.notificationIdentifier = identifier
        } catch {
            // Notification scheduling failed — non-fatal
        }
    }

    // MARK: - Cancel & Reschedule

    /// Cancels all notifications for a schedule's steps.
    func cancelNotifications(for steps: [ScheduleStep]) {
        let identifiers = steps.compactMap(\.notificationIdentifier)
            + steps.flatMap(\.subSteps).compactMap(\.notificationIdentifier)
        guard !identifiers.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    /// Reschedules notifications after a timeline change (e.g., cold retard adjustment).
    func rescheduleNotifications(for steps: [ScheduleStep]) async {
        cancelNotifications(for: steps)
        await scheduleNotifications(for: steps)
    }

    /// Cancels all pending Doug notifications.
    func cancelAll() {
        center.removeAllPendingNotificationRequests()
    }

    // MARK: - Starter Feed Reminders

    /// Schedules (or replaces) the single pending starter feed reminder.
    /// Uses a stable identifier so repeated calls don't stack up notifications.
    func scheduleStarterFeedReminder(at date: Date, context: String) async {
        let authorized = await requestAuthorization()
        guard authorized, date > Date() else {
            cancelStarterFeedReminder()
            return
        }

        // Replace any existing reminder.
        cancelStarterFeedReminder()

        let content = UNMutableNotificationContent()
        content.title = "Time to Feed Your Starter"
        content.body = context
        content.sound = .default
        content.categoryIdentifier = Category.starterFeed

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: max(date.timeIntervalSinceNow, 1),
            repeats: false
        )

        let request = UNNotificationRequest(
            identifier: Self.starterFeedIdentifier,
            content: content,
            trigger: trigger
        )

        try? await center.add(request)
    }

    func cancelStarterFeedReminder() {
        center.removePendingNotificationRequests(
            withIdentifiers: [Self.starterFeedIdentifier]
        )
    }
}
