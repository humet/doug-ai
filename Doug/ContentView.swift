import SwiftUI
import SwiftData

struct ContentView: View {
    @Query private var availabilities: [UserAvailability]
    @State private var hasCompletedOnboarding = false

    private var needsOnboarding: Bool {
        availabilities.isEmpty && !hasCompletedOnboarding
    }

    var body: some View {
        if needsOnboarding {
            OnboardingView {
                hasCompletedOnboarding = true
            }
        } else {
            TabView {
                Tab("Schedule", systemImage: "calendar.badge.clock") {
                    ScheduleTab()
                }

                Tab("Starter", systemImage: "bubbles.and.sparkles") {
                    StarterTab()
                }

                Tab("Calculator", systemImage: "function") {
                    CalculatorTab()
                }

                Tab("Settings", systemImage: "gear") {
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
