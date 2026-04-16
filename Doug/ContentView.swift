import SwiftUI
import SwiftData

struct ContentView: View {
    var body: some View {
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
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Schedule.self, inMemory: true)
}
