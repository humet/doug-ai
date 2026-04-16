import Foundation
import SwiftData
import UserNotifications

/// Responds to interactive notification actions — currently starter feed "Log Feed" and "Snooze 1h".
@MainActor
final class NotificationActionHandler: NSObject, UNUserNotificationCenterDelegate {
    private let modelContainer: ModelContainer

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        super.init()
    }

    /// Show banners even when the app is foregrounded.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let actionIdentifier = response.actionIdentifier
        let categoryIdentifier = response.notification.request.content.categoryIdentifier
        let userInfo = response.notification.request.content.userInfo
        let stepTypeID = userInfo["stepTypeID"] as? String
        let sequenceIndex = userInfo["sequenceIndex"] as? Int

        Task { @MainActor in
            switch categoryIdentifier {
            case NotificationService.Category.starterFeed:
                switch actionIdentifier {
                case NotificationService.Action.logFeed:
                    self.logFeedFromNotification()
                case NotificationService.Action.snoozeFeed:
                    await self.snoozeFeedReminder()
                default:
                    break
                }
            case NotificationService.Category.foldStep:
                if actionIdentifier == UNNotificationDefaultActionIdentifier,
                   let stepTypeID, let sequenceIndex {
                    NotificationRouter.shared.requestFoldEntry(
                        stepTypeID: stepTypeID,
                        sequenceIndex: sequenceIndex
                    )
                }
            case NotificationService.Category.coldRetardEnd:
                if actionIdentifier == UNNotificationDefaultActionIdentifier {
                    NotificationRouter.shared.focusScheduleTab()
                }
            default:
                break
            }
            completionHandler()
        }
    }

    // MARK: - Starter feed actions

    private func logFeedFromNotification() {
        let context = ModelContext(modelContainer)

        // Reuse the most recent feed's ratio and flour type so the log reflects the user's usual habit.
        var descriptor = FetchDescriptor<StarterFeedLog>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        let lastLog = (try? context.fetch(descriptor))?.first

        let log = StarterFeedLog(
            ratioStarter: lastLog?.ratioStarter ?? 1,
            ratioFlour: lastLog?.ratioFlour ?? 5,
            ratioWater: lastLog?.ratioWater ?? 5,
            flourType: lastLog?.flourType ?? "white",
            kitchenTemperatureCelsius: lastLog?.kitchenTemperatureCelsius ?? 22
        )
        context.insert(log)
        try? context.save()

        NotificationService.shared.cancelStarterFeedReminder()
    }

    private func snoozeFeedReminder() async {
        let snoozeDate = Date().addingTimeInterval(60 * 60)
        await NotificationService.shared.scheduleStarterFeedReminder(
            at: snoozeDate,
            context: "Snoozed — feed your starter when you get a moment."
        )
    }
}
