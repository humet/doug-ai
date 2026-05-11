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
        _notificationHandler = State(initialValue: NotificationActionHandler(modelContainer: container))
    }

    private static func makeContainer() -> ModelContainer {
        let schema = Schema(versionedSchema: DougSchemaV2.self)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(
                for: schema,
                migrationPlan: DougMigrationPlan.self,
                configurations: [config]
            )
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
