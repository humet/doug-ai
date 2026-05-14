import SwiftData
import SwiftUI

struct SettingsView: View {
    @Query private var availabilities: [UserAvailability]
    @Query private var windows: [UnavailableWindow]
    @Query private var profiles: [StarterProfile]
    @Query private var feedLogs: [StarterFeedLog]
    @Environment(\.modelContext) private var modelContext

    @State private var showAddWindow = false

    private var availability: UserAvailability {
        if let existing = availabilities.first { return existing }
        let new = UserAvailability()
        modelContext.insert(new)
        return new
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker(
                        "Available from",
                        selection: Binding(
                            get: { dateFrom(hour: availability.dailyStartHour, minute: availability.dailyStartMinute) },
                            set: { newValue in
                                let comps = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                                availability.dailyStartHour = comps.hour ?? 6
                                availability.dailyStartMinute = comps.minute ?? 30
                            }
                        ),
                        displayedComponents: .hourAndMinute
                    )

                    DatePicker(
                        "Available until",
                        selection: Binding(
                            get: { dateFrom(hour: availability.dailyEndHour, minute: availability.dailyEndMinute) },
                            set: { newValue in
                                let comps = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                                availability.dailyEndHour = comps.hour ?? 21
                                availability.dailyEndMinute = comps.minute ?? 0
                            }
                        ),
                        displayedComponents: .hourAndMinute
                    )
                } header: {
                    Text("Daily Available Hours")
                } footer: {
                    Text("Hands-on baking steps won't be scheduled outside these hours.")
                }

                Section {
                    ForEach(windows) { window in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(window.name)
                                    .font(.subheadline.bold())
                                Spacer()
                                if !window.isActive {
                                    Text("Disabled")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            HStack {
                                Text(timeString(hour: window.startHour, minute: window.startMinute))
                                Text("–")
                                Text(timeString(hour: window.endHour, minute: window.endMinute))
                                if window.isRecurring {
                                    Spacer()
                                    Text(daysString(window.daysOfWeek))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            modelContext.delete(windows[index])
                        }
                    }

                    Button {
                        showAddWindow = true
                    } label: {
                        Label("Add Window", systemImage: "plus")
                    }
                } header: {
                    Text("Unavailable Windows")
                } footer: {
                    Text("Times when you can't do hands-on baking steps (school run, gym, work, etc.)")
                }

                if let profile = profiles.first {
                    Section {
                        Picker("Storage", selection: Binding(
                            get: { profile.starterStorageType },
                            set: { profile.starterStorageType = $0 }
                        )) {
                            Text("Fridge").tag(StarterStorageType.fridge)
                            Text("Counter").tag(StarterStorageType.counter)
                        }

                        Stepper(
                            "Maintenance cycle: \(Int(profile.maintenanceCycleDays)) days",
                            value: Binding(
                                get: { profile.maintenanceCycleDays },
                                set: { profile.maintenanceCycleDays = $0 }
                            ),
                            in: 1 ... 14,
                            step: 1
                        )
                    } header: {
                        Text("Starter Settings")
                    }
                }

                #if DEBUG
                    debugSection
                #endif
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("Settings")
            .sheet(isPresented: $showAddWindow) {
                AddUnavailableWindowSheet(modelContext: modelContext)
            }
        }
    }

    #if DEBUG
        private var debugSection: some View {
            Section {
                Button {
                    seedHealthyStarter()
                } label: {
                    Label("Seed healthy starter", systemImage: "testtube.2")
                }

                Button {
                    seedStaleStarter()
                } label: {
                    Label("Seed stale starter (needs revival)", systemImage: "exclamationmark.triangle")
                }
            } header: {
                Text("Debug")
            } footer: {
                Text(
                    "Healthy: recent peaked feed → readyToBake. Stale: last feed 14 days ago → needsRevival, unlocks the Start Revival button."
                )
            }
        }

        private func seedHealthyStarter() {
            if profiles.isEmpty {
                modelContext.insert(StarterProfile(storageType: .fridge))
            }

            let now = Date()
            let feed = StarterFeedLog(
                timestamp: now.addingTimeInterval(-2 * 60 * 60),
                ratioStarter: 1,
                ratioFlour: 5,
                ratioWater: 5,
                flourType: "white",
                kitchenTemperatureCelsius: 22
            )
            feed.markPeak(at: now.addingTimeInterval(-60 * 60))
            modelContext.insert(feed)
        }

        private func seedStaleStarter() {
            if profiles.isEmpty {
                modelContext.insert(StarterProfile(storageType: .fridge))
            }

            // Clear any existing feed logs so the stale one is most recent.
            for existing in feedLogs {
                modelContext.delete(existing)
            }

            let now = Date()
            let feed = StarterFeedLog(
                timestamp: now.addingTimeInterval(-14 * 86400), // 14 days ago
                ratioStarter: 1,
                ratioFlour: 5,
                ratioWater: 5,
                flourType: "white",
                kitchenTemperatureCelsius: 22
            )
            modelContext.insert(feed)
        }
    #endif

    private func dateFrom(hour: Int, minute: Int) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
    }

    private func timeString(hour: Int, minute: Int) -> String {
        String(format: "%d:%02d", hour, minute)
    }

    private func daysString(_ days: [Int]) -> String {
        let symbols = Calendar.current.shortWeekdaySymbols
        return days.sorted().compactMap { day in
            guard day >= 1, day <= 7 else { return nil }
            return symbols[day - 1]
        }.joined(separator: ", ")
    }
}

// MARK: - Add Unavailable Window

struct AddUnavailableWindowSheet: View {
    let modelContext: ModelContext

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var isRecurring = true
    @State private var selectedDays: Set<Int> = []
    @State private var startTime = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var endTime = Calendar.current.date(bySettingHour: 17, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var specificDate = Date()

    private let weekdays = Array(1 ... 7) // 1=Sun, 7=Sat

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Name (e.g., School Run)", text: $name)
                    Toggle("Recurring", isOn: $isRecurring)
                }

                if isRecurring {
                    Section("Days") {
                        ForEach(weekdays, id: \.self) { day in
                            let symbol = Calendar.current.weekdaySymbols[day - 1]
                            Toggle(symbol, isOn: Binding(
                                get: { selectedDays.contains(day) },
                                set: { isOn in
                                    if isOn { selectedDays.insert(day) }
                                    else { selectedDays.remove(day) }
                                }
                            ))
                        }
                    }
                } else {
                    Section("Date") {
                        DatePicker("Date", selection: $specificDate, displayedComponents: .date)
                    }
                }

                Section("Time") {
                    DatePicker("Start", selection: $startTime, displayedComponents: .hourAndMinute)
                    DatePicker("End", selection: $endTime, displayedComponents: .hourAndMinute)
                }
            }
            .navigationTitle("Add Window")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }
                    .disabled(name.isEmpty)
                }
            }
        }
    }

    private func save() {
        let startComps = Calendar.current.dateComponents([.hour, .minute], from: startTime)
        let endComps = Calendar.current.dateComponents([.hour, .minute], from: endTime)

        let window = UnavailableWindow(
            name: name,
            isRecurring: isRecurring,
            daysOfWeek: isRecurring ? Array(selectedDays) : [],
            startHour: startComps.hour ?? 9,
            startMinute: startComps.minute ?? 0,
            endHour: endComps.hour ?? 17,
            endMinute: endComps.minute ?? 0,
            specificDate: isRecurring ? nil : specificDate
        )
        modelContext.insert(window)
        dismiss()
    }
}
