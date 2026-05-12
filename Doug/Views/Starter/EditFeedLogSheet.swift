import SwiftData
import SwiftUI

struct EditFeedLogSheet: View {
    @Bindable var log: StarterFeedLog
    let profile: StarterProfile?
    let allLogs: [StarterFeedLog]
    @Bindable var viewModel: StarterViewModel

    @Environment(\.dismiss) private var dismiss

    @State private var timestamp: Date
    @State private var ratioStarter: Int
    @State private var ratioFlour: Int
    @State private var ratioWater: Int
    @State private var flourType: String
    @State private var kitchenTemp: Double
    @State private var starterGrams: String

    init(log: StarterFeedLog, profile: StarterProfile?, allLogs: [StarterFeedLog], viewModel: StarterViewModel) {
        self.log = log
        self.profile = profile
        self.allLogs = allLogs
        self.viewModel = viewModel
        _timestamp = State(initialValue: log.timestamp)
        _ratioStarter = State(initialValue: log.ratioStarter)
        _ratioFlour = State(initialValue: log.ratioFlour)
        _ratioWater = State(initialValue: log.ratioWater)
        _flourType = State(initialValue: log.flourType)
        _kitchenTemp = State(initialValue: log.kitchenTemperatureCelsius)
        _starterGrams = State(initialValue: log.starterGrams.map { String(Int($0)) } ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Date & Time") {
                    DatePicker("Fed at", selection: $timestamp, in: ...Date())
                }

                Section("Ratio") {
                    Stepper("Starter: \(ratioStarter)", value: $ratioStarter, in: 1 ... 10)
                    Stepper("Flour: \(ratioFlour)", value: $ratioFlour, in: 1 ... 20)
                    Stepper("Water: \(ratioWater)", value: $ratioWater, in: 1 ... 20)
                }

                Section {
                    HStack {
                        Text("Starter amount")
                        Spacer()
                        TextField("optional", text: $starterGrams)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 100)
                        Text("g")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Amount")
                }

                Section("Details") {
                    HStack {
                        Text("Flour")
                        Spacer()
                        TextField("e.g. white, 50/50 white/rye", text: $flourType)
                            .multilineTextAlignment(.trailing)
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("Kitchen temp")
                        Spacer()
                        Text("\(Int(kitchenTemp))°C")
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $kitchenTemp, in: 16 ... 32, step: 1)
                }

                if log.peakTimestamp != nil {
                    Section {
                        Button("Clear Peak Data", role: .destructive) {
                            log.peakTimestamp = nil
                            log.timeToPeakMinutes = nil
                        }
                    } footer: {
                        Text("Removes the recorded peak time so you can mark it again.")
                    }
                }
            }
            .navigationTitle("Edit Feed")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        applyChanges()
                        dismiss()
                    }
                }
            }
        }
    }

    private func applyChanges() {
        let timestampChanged = abs(log.timestamp.timeIntervalSince(timestamp)) > 60
        log.timestamp = timestamp
        log.ratioStarter = ratioStarter
        log.ratioFlour = ratioFlour
        log.ratioWater = ratioWater
        log.flourType = flourType
        log.kitchenTemperatureCelsius = kitchenTemp
        log.starterGrams = Double(starterGrams.trimmingCharacters(in: .whitespaces))

        if timestampChanged, let peak = log.peakTimestamp {
            log.timeToPeakMinutes = peak.timeIntervalSince(timestamp) / 60.0
        }

        viewModel.updateProfileAverages(profile: profile, feedLogs: allLogs)
    }
}
