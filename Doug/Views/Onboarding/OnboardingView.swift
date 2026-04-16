import SwiftUI
import SwiftData

struct OnboardingView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var startHour = 6
    @State private var startMinute = 30
    @State private var endHour = 21
    @State private var endMinute = 0
    @State private var kitchenTemp = 22.0
    @State private var starterStorage: StarterStorageType = .fridge

    let onComplete: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Let's set up Doug to work around your schedule.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Section {
                    DatePicker(
                        "Available from",
                        selection: Binding(
                            get: { dateFrom(hour: startHour, minute: startMinute) },
                            set: { val in
                                let c = Calendar.current.dateComponents([.hour, .minute], from: val)
                                startHour = c.hour ?? 6
                                startMinute = c.minute ?? 30
                            }
                        ),
                        displayedComponents: .hourAndMinute
                    )

                    DatePicker(
                        "Available until",
                        selection: Binding(
                            get: { dateFrom(hour: endHour, minute: endMinute) },
                            set: { val in
                                let c = Calendar.current.dateComponents([.hour, .minute], from: val)
                                endHour = c.hour ?? 21
                                endMinute = c.minute ?? 0
                            }
                        ),
                        displayedComponents: .hourAndMinute
                    )
                } header: {
                    Text("When Can You Bake?")
                } footer: {
                    Text("Hands-on steps like mixing and shaping will only be scheduled during these hours.")
                }

                Section {
                    HStack {
                        Text("Kitchen temperature")
                        Spacer()
                        Text("\(Int(kitchenTemp))°C")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $kitchenTemp, in: 16...32, step: 1)
                } header: {
                    Text("Kitchen Temperature")
                } footer: {
                    Text("Used to estimate fermentation times. You can adjust this for each bake.")
                }

                Section {
                    Picker("Starter storage", selection: $starterStorage) {
                        Text("Fridge").tag(StarterStorageType.fridge)
                        Text("Counter").tag(StarterStorageType.counter)
                    }
                } header: {
                    Text("Starter")
                }

                Section {
                    Button {
                        completeOnboarding()
                    } label: {
                        Text("Get Started")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .navigationTitle("Welcome to Doug")
        }
    }

    private func completeOnboarding() {
        let availability = UserAvailability(
            dailyStartHour: startHour,
            dailyStartMinute: startMinute,
            dailyEndHour: endHour,
            dailyEndMinute: endMinute
        )
        modelContext.insert(availability)

        let profile = StarterProfile(
            storageType: starterStorage,
            maintenanceCycleDays: starterStorage == .fridge ? 6 : 1
        )
        modelContext.insert(profile)

        onComplete()
    }

    private func dateFrom(hour: Int, minute: Int) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
    }
}
