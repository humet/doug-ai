import SwiftData
import SwiftUI

struct ContentView: View {
    @Query private var availabilities: [UserAvailability]
    @State private var hasCompletedOnboarding = false
    @State private var router = NotificationRouter.shared
    @State private var toasts = ToastCenter.shared

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

                Tab("History", systemImage: "book.closed", value: NotificationRouter.Tab.history) {
                    HistoryTab()
                }

                Tab("Settings", systemImage: "gear", value: NotificationRouter.Tab.settings) {
                    SettingsView()
                }
            }
            .toolbarBackgroundVisibility(.hidden, for: .tabBar)
            .background(DougTheme.warmCream.ignoresSafeArea())
            .overlay(alignment: .bottom) {
                if let message = toasts.message {
                    ToastBanner(message: message)
                        .padding(.bottom, 60) // clear the tab bar
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(duration: 0.3), value: toasts.message)
            // Success tap when a confirmation appears (not when it clears).
            .sensoryFeedback(.success, trigger: toasts.message) { _, newValue in
                newValue != nil
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Schedule.self, inMemory: true)
}
