import SwiftData
import SwiftUI
import UserNotifications

@main
struct DougApp: App {
    let sharedModelContainer: ModelContainer
    @State private var notificationHandler: NotificationActionHandler

    init() {
        let container = Self.makeContainer()
        sharedModelContainer = container
        let handler = NotificationActionHandler(modelContainer: container)
        _notificationHandler = State(initialValue: handler)
        // The delegate must be live before launch finishes: notification
        // actions (e.g. snooze) background-launch the app and deliver the
        // response immediately — a .task-assigned delegate would miss them.
        UNUserNotificationCenter.current().delegate = handler
        NotificationService.shared.registerCategories()
        // Live Activity buttons perform in the app process — possibly a
        // background launch where no view (and no view model) exists yet.
        LiveActivityIntentRunner.modelContainer = container
        CompleteBakePhaseIntent.performHandler = { stepTypeID, sequenceIndex in
            LiveActivityIntentRunner.completeBakePhase(
                stepTypeID: stepTypeID,
                sequenceIndex: sequenceIndex
            )
        }
    }

    private static func makeContainer() -> ModelContainer {
        let schema = Schema([
            Schedule.self,
            ScheduleStep.self,
            DoughTemperatureReading.self,
            BakeFermentationProfile.self,
            BakePhoto.self,
            StarterFeedLog.self,
            StarterProfile.self,
            RevivalPlan.self,
            RevivalFeedStep.self,
            UserAvailability.self,
            UnavailableWindow.self,
            CoachMessage.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    reconcileLiveActivities()
                }
        }
        .modelContainer(sharedModelContainer)
    }

    @MainActor
    private func reconcileLiveActivities() {
        let context = sharedModelContainer.mainContext
        let activeSchedule: Schedule? = {
            let descriptor = FetchDescriptor<Schedule>(
                predicate: #Predicate { $0.status == "active" }
            )
            do {
                return try context.fetch(descriptor).first
            } catch {
                print("Failed to fetch active schedule for Live Activity reconciliation: \(error)")
                return nil
            }
        }()
        let activeRevivalPlan: RevivalPlan? = {
            let descriptor = FetchDescriptor<RevivalPlan>(
                predicate: #Predicate { $0.status == "active" }
            )
            do {
                return try context.fetch(descriptor).first
            } catch {
                print("Failed to fetch active revival plan for Live Activity reconciliation: \(error)")
                return nil
            }
        }()
        LiveActivityService.shared.reconcileOnLaunch(
            activeSchedule: activeSchedule,
            activeRevivalPlan: activeRevivalPlan
        )
    }
}
