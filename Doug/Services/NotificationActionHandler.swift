import Foundation
import SwiftData
import UserNotifications

/// Responds to notification taps and action buttons.
@MainActor
final class NotificationActionHandler: NSObject, UNUserNotificationCenterDelegate {
    private let modelContainer: ModelContainer

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        super.init()
    }

    /// What a notification response should do — derived purely from the
    /// response's category, action, and step info, separated from execution so
    /// every tap behavior is unit-testable without UNUserNotificationCenter.
    enum RoutedAction: Equatable {
        case openStarterTab
        case openStarterLogFeed
        /// Re-deliver the same notification `minutes` from now.
        case snoozeSame(minutes: Int)
        case foldEntry(stepTypeID: String, sequenceIndex: Int)
        case stepDetail(stepTypeID: String, sequenceIndex: Int)
        case bakeDone(stepTypeID: String, sequenceIndex: Int)
        case focusScheduleTab
        case none
    }

    nonisolated static func route(
        categoryIdentifier: String,
        actionIdentifier: String,
        stepTypeID: String?,
        sequenceIndex: Int?
    ) -> RoutedAction {
        switch categoryIdentifier {
        case NotificationService.Category.starterFeed:
            routeStarterFeed(actionIdentifier)
        case NotificationService.Category.revivalMix:
            routeRevivalMix(actionIdentifier)
        case NotificationService.Category.foldStep:
            routeFoldStep(actionIdentifier, stepTypeID, sequenceIndex)
        case NotificationService.Category.handsOnStep,
             NotificationService.Category.coldRetardEnd:
            routeHandsOnStep(actionIdentifier, stepTypeID, sequenceIndex)
        case NotificationService.Category.bakePhase:
            routeBakePhase(actionIdentifier, stepTypeID, sequenceIndex)
        default:
            .none
        }
    }

    private nonisolated static func routeStarterFeed(_ action: String) -> RoutedAction {
        switch action {
        case NotificationService.Action.logFeed: .openStarterLogFeed
        case NotificationService.Action.snoozeFeed: .snoozeSame(minutes: 60)
        case UNNotificationDefaultActionIdentifier: .openStarterTab
        default: .none
        }
    }

    private nonisolated static func routeRevivalMix(_ action: String) -> RoutedAction {
        switch action {
        case NotificationService.Action.snoozeStep: .snoozeSame(minutes: 30)
        case UNNotificationDefaultActionIdentifier: .openStarterTab
        default: .none
        }
    }

    private nonisolated static func routeFoldStep(
        _ action: String, _ stepTypeID: String?, _ sequenceIndex: Int?
    ) -> RoutedAction {
        switch action {
        case UNNotificationDefaultActionIdentifier:
            if let stepTypeID, let sequenceIndex {
                return .foldEntry(stepTypeID: stepTypeID, sequenceIndex: sequenceIndex)
            }
            return .focusScheduleTab
        case NotificationService.Action.snoozeStep:
            return .snoozeSame(minutes: 30)
        default:
            return .none
        }
    }

    private nonisolated static func routeHandsOnStep(
        _ action: String, _ stepTypeID: String?, _ sequenceIndex: Int?
    ) -> RoutedAction {
        switch action {
        case UNNotificationDefaultActionIdentifier:
            if let stepTypeID, let sequenceIndex {
                return .stepDetail(stepTypeID: stepTypeID, sequenceIndex: sequenceIndex)
            }
            return .focusScheduleTab
        case NotificationService.Action.snoozeStep:
            return .snoozeSame(minutes: 30)
        default:
            return .none
        }
    }

    private nonisolated static func routeBakePhase(
        _ action: String, _ stepTypeID: String?, _ sequenceIndex: Int?
    ) -> RoutedAction {
        switch action {
        case NotificationService.Action.markBakePhaseDone:
            if let stepTypeID, let sequenceIndex {
                return .bakeDone(stepTypeID: stepTypeID, sequenceIndex: sequenceIndex)
            }
            return .focusScheduleTab
        case UNNotificationDefaultActionIdentifier:
            if let stepTypeID, let sequenceIndex {
                return .stepDetail(stepTypeID: stepTypeID, sequenceIndex: sequenceIndex)
            }
            return .focusScheduleTab
        default:
            return .none
        }
    }

    /// Show banners even when the app is foregrounded.
    nonisolated func userNotificationCenter(
        _: UNUserNotificationCenter,
        willPresent _: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }

    nonisolated func userNotificationCenter(
        _: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let request = response.notification.request
        let identifier = request.identifier
        let content = request.content
        let userInfo = content.userInfo
        let routed = Self.route(
            categoryIdentifier: content.categoryIdentifier,
            actionIdentifier: response.actionIdentifier,
            stepTypeID: userInfo["stepTypeID"] as? String,
            sequenceIndex: userInfo["sequenceIndex"] as? Int
        )

        Task { @MainActor in
            await self.perform(routed, identifier: identifier, content: content)
            completionHandler()
        }
    }

    private func perform(
        _ action: RoutedAction,
        identifier: String,
        content: UNNotificationContent
    ) async {
        switch action {
        case .openStarterTab:
            NotificationRouter.shared.focusStarterTab()
        case .openStarterLogFeed:
            NotificationRouter.shared.requestStarterLogFeed()
        case let .snoozeSame(minutes):
            await NotificationService.shared.snoozeDelivered(
                identifier: identifier,
                content: content,
                minutes: minutes
            )
        case let .foldEntry(stepTypeID, sequenceIndex):
            NotificationRouter.shared.requestFoldEntry(
                stepTypeID: stepTypeID,
                sequenceIndex: sequenceIndex
            )
        case let .stepDetail(stepTypeID, sequenceIndex):
            NotificationRouter.shared.requestStepDetail(
                stepTypeID: stepTypeID,
                sequenceIndex: sequenceIndex
            )
        case let .bakeDone(stepTypeID, sequenceIndex):
            NotificationRouter.shared.markBakeSubStepDone(
                stepTypeID: stepTypeID,
                sequenceIndex: sequenceIndex
            )
        case .focusScheduleTab:
            NotificationRouter.shared.focusScheduleTab()
        case .none:
            break
        }
    }
}
