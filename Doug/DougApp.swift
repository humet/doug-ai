import SwiftUI
import SwiftData
import UserNotifications

@main
struct DougApp: App {
    let sharedModelContainer: ModelContainer
    @State private var notificationHandler: NotificationActionHandler

    init() {
        let container = Self.makeContainer()
        self.sharedModelContainer = container
        _notificationHandler = State(initialValue: NotificationActionHandler(modelContainer: container))
    }

    private static func makeContainer() -> ModelContainer {
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
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    NotificationService.shared.registerCategories()
                    UNUserNotificationCenter.current().delegate = notificationHandler
                }
        }
        .modelContainer(sharedModelContainer)
    }
}
