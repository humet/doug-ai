import SwiftUI
import SwiftData

struct ContentView: View {
    @Query private var availabilities: [UserAvailability]
    @State private var hasCompletedOnboarding = false
    @State private var router = NotificationRouter.shared

    private var needsOnboarding: Bool {
        availabilities.isEmpty && !hasCompletedOnboarding
    }

    var body: some View {
        if needsOnboarding {
            OnboardingView {
                hasCompletedOnboarding = true
            }
        } else {
            @Bindable var router = router
            TabView(selection: $router.selectedTab) {
                Tab("Schedule", systemImage: "calendar.badge.clock", value: NotificationRouter.Tab.schedule) {
                    ScheduleTab()
                }

                Tab("Starter", systemImage: "bubbles.and.sparkles", value: NotificationRouter.Tab.starter) {
                    StarterTab()
                }

                Tab("Calculator", systemImage: "function", value: NotificationRouter.Tab.calculator) {
                    CalculatorTab()
                }

                Tab("Settings", systemImage: "gear", value: NotificationRouter.Tab.settings) {
                    SettingsView()
                }
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Schedule.self, inMemory: true)
}
