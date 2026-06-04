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
        static let bakePhase = "BAKE_PHASE"
        static let starterFeed = "STARTER_FEED"
    }

    /// Action identifiers for interactive notifications.
    enum Action {
        static let logFeed = "LOG_FEED"
        static let snoozeFeed = "SNOOZE_FEED_1H"
        static let snoozeStep = "SNOOZE_STEP_30M"
        static let markBakePhaseDone = "MARK_BAKE_PHASE_DONE"
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

        let markDoneAction = UNNotificationAction(
            identifier: Action.markBakePhaseDone,
            title: "Done",
            options: [.foreground]
        )
        let bakePhaseCategory = UNNotificationCategory(
            identifier: Category.bakePhase,
            actions: [markDoneAction, snoozeStepAction],
            intentIdentifiers: [],
            options: []
        )

        center.setNotificationCategories([
            starterFeedCategory,
            handsOnStepCategory,
            foldStepCategory,
            bakePhaseCategory,
        ])
    }

    // MARK: - Schedule Notifications

    /// Schedules notifications for hands-on steps (5 min before start),
    /// passive-flexible steps (at timer completion), and bake substep transitions.
    func scheduleNotifications(for steps: [ScheduleStep]) async {
        let authorized = await requestAuthorization()
        guard authorized else { return }

        for step in steps {
            let stepType = step.stepType

            if stepType.classification == .passiveFlexible {
                await scheduleFlexibleCompletionNotification(step: step)
                continue
            }

            if stepType.id == .bake {
                for subStep in step.subSteps {
                    await scheduleBakePhaseNotification(step: subStep)
                }
                continue
            }

            guard stepType.classification == .handsOn || stepType.id == .preheat else {
                continue
            }

            await scheduleStepNotification(step: step)

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
        content.body = StepTypeRegistry.notificationText(for: stepType.id, recipe: step.schedule?.recipe)
        content.sound = .default

        if stepType.requiresTempReading {
            content.categoryIdentifier = Category.foldStep
        } else if stepType.id == .preheat {
            content.categoryIdentifier = Category.coldRetardEnd
            content.interruptionLevel = .timeSensitive
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

    private func scheduleFlexibleCompletionNotification(step: ScheduleStep) async {
        let notifTime = step.computedEndTime
        guard notifTime > Date() else { return }

        let content = UNMutableNotificationContent()
        content.title = "\(step.stepType.label) Timer Complete"
        content.body = "Move on when your dough is ready."
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        content.categoryIdentifier = Category.handsOnStep
        content.userInfo = [
            "stepTypeID": step.stepTypeID,
            "sequenceIndex": step.sequenceIndex,
        ]

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: max(notifTime.timeIntervalSinceNow, 1),
            repeats: false
        )

        let identifier = "step-\(step.stepTypeID)-\(step.sequenceIndex)-complete"
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: trigger
        )

        do {
            try await center.add(request)
            step.notificationIdentifier = identifier
        } catch {}
    }

    private func scheduleBakePhaseNotification(step: ScheduleStep) async {
        let notifTime = step.computedEndTime
        guard notifTime > Date() else { return }

        let isCovered = step.stepTypeID == StepTypeID.bakeCovered.rawValue
        let content = UNMutableNotificationContent()
        content.title = isCovered ? "Remove the Lid" : "Your Bread Is Ready!"
        content.body = isCovered
            ? "The covered bake is done. Remove the lid to develop the crust."
            : "Take your loaf out and let it cool on a wire rack."
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        content.categoryIdentifier = Category.bakePhase
        content.userInfo = [
            "stepTypeID": step.stepTypeID,
            "sequenceIndex": step.sequenceIndex,
        ]

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: max(notifTime.timeIntervalSinceNow, 1),
            repeats: false
        )

        let identifier = "step-\(step.stepTypeID)-\(step.sequenceIndex)-bake-phase"
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: trigger
        )

        do {
            try await center.add(request)
            step.notificationIdentifier = identifier
        } catch {}
    }

    // MARK: - Refeed Reminder

    private static let refeedReminderIdentifier = "refeed-starter-reminder"

    func scheduleRefeedReminder(at date: Date) async {
        guard date > Date() else { return }
        let authorized = await requestAuthorization()
        guard authorized else { return }

        let content = UNMutableNotificationContent()
        content.title = "Feed & Refrigerate Your Starter"
        content.body = "Your autolyse is resting — good time to feed your starter and put it back in the fridge."
        content.sound = .default
        content.categoryIdentifier = Category.starterFeed

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: max(date.timeIntervalSinceNow, 1),
            repeats: false
        )

        let request = UNNotificationRequest(
            identifier: Self.refeedReminderIdentifier,
            content: content,
            trigger: trigger
        )

        do {
            try await center.add(request)
        } catch {}
    }

    func cancelRefeedReminder() {
        center.removePendingNotificationRequests(withIdentifiers: [Self.refeedReminderIdentifier])
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

    // MARK: - Revival Mix Reminders

    private static func revivalMixIdentifier(planID: String, stepIndex: Int) -> String {
        "revival-mix-\(planID)-\(stepIndex)"
    }

    /// Schedules a one-shot reminder to mix the next revival feed at the given time.
    func scheduleRevivalMixReminder(
        at date: Date,
        planID: String,
        stepIndex: Int,
        title: String
    ) async {
        let authorized = await requestAuthorization()
        guard authorized, date > Date() else { return }

        let identifier = Self.revivalMixIdentifier(planID: planID, stepIndex: stepIndex)
        center.removePendingNotificationRequests(withIdentifiers: [identifier])

        let content = UNMutableNotificationContent()
        content.title = "Time to mix your starter"
        content.body = title
        content.sound = .default
        content.categoryIdentifier = Category.starterFeed

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: max(date.timeIntervalSinceNow, 1),
            repeats: false
        )

        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: trigger
        )

        try? await center.add(request)
    }

    func cancelRevivalMixReminder(planID: String, stepIndex: Int) {
        center.removePendingNotificationRequests(
            withIdentifiers: [Self.revivalMixIdentifier(planID: planID, stepIndex: stepIndex)]
        )
    }

    /// Whether the OS has a pending mix reminder matching the given plan + step.
    /// Lets the UI survive navigation — it can re-derive button state on appear.
    func hasPendingRevivalMixReminder(planID: String, stepIndex: Int) async -> Bool {
        let target = Self.revivalMixIdentifier(planID: planID, stepIndex: stepIndex)
        let pending = await center.pendingNotificationRequests()
        return pending.contains { $0.identifier == target }
    }

    /// Reschedules a revival mix reminder only if one was already pending.
    /// Returns true if a reminder was found and rescheduled.
    @discardableResult
    func rescheduleRevivalMixReminderIfPending(
        at date: Date,
        planID: String,
        stepIndex: Int,
        title: String
    ) async -> Bool {
        let target = Self.revivalMixIdentifier(planID: planID, stepIndex: stepIndex)
        let pending = await center.pendingNotificationRequests()
        guard pending.contains(where: { $0.identifier == target }) else { return false }
        cancelRevivalMixReminder(planID: planID, stepIndex: stepIndex)
        await scheduleRevivalMixReminder(at: date, planID: planID, stepIndex: stepIndex, title: title)
        return true
    }

    /// Cancels all revival mix reminders for a plan.
    func cancelAllRevivalReminders(planID: String, stepCount: Int) {
        let identifiers = (0 ..< stepCount).map { Self.revivalMixIdentifier(planID: planID, stepIndex: $0) }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }
}
