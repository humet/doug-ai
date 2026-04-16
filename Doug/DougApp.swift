import SwiftUI
import SwiftData

@main
struct DougApp: App {
    var sharedModelContainer: ModelContainer = {
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
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
