import SwiftUI
import SwiftData

/// View for logging dough temperature at each fold during an active bake.
///
/// Deep-linked from fold notifications. Shows current fold context,
/// temperature input, and accumulated degree-hour progress.
struct TemperatureEntryView: View {
    let schedule: Schedule
    let foldStep: ScheduleStep?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var temperatureCelsius: Double = 24.0
    @State private var aliquotRisePercent: String = ""

    private var existingReadings: [DoughTemperatureReading] {
        (schedule.temperatureReadings).sorted { $0.timestamp < $1.timestamp }
    }

    private var currentDegreeHours: Double {
        let pairs = existingReadings.map {
            (timestamp: $0.timestamp, temperatureCelsius: $0.temperatureCelsius)
        }
        return DegreeHourCalculator.accumulatedDegreeHours(readings: pairs)
    }

    private var targetDegreeHours: Double {
        schedule.recipe.degreeHourTarget
    }

    private var progress: Double {
        DegreeHourCalculator.progress(
            currentDegreeHours: currentDegreeHours,
            targetDegreeHours: targetDegreeHours
        )
    }

    private var estimatedMinutesRemaining: Double? {
        DegreeHourCalculator.estimatedMinutesRemaining(
            currentDegreeHours: currentDegreeHours,
            targetDegreeHours: targetDegreeHours,
            latestTempCelsius: existingReadings.last?.temperatureCelsius ?? temperatureCelsius
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let fold = foldStep {
                        Label(fold.stepType.label, systemImage: "hand.raised")
                            .font(.headline)
                        Text(fold.stepType.instructionText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Current Step")
                }

                Section {
                    HStack {
                        Text("Dough temperature")
                        Spacer()
                        Text(String(format: "%.1f°C", temperatureCelsius))
                            .font(.title3.bold().monospacedDigit())
                    }
                    Slider(value: $temperatureCelsius, in: 18...35, step: 0.5)
                        .accessibilityLabel("Dough temperature")
                        .accessibilityValue(String(format: "%.1f degrees", temperatureCelsius))
                } header: {
                    Text("Temperature Reading")
                }

                Section {
                    TextField("Rise % (optional)", text: $aliquotRisePercent)
                        .keyboardType(.decimalPad)
                } header: {
                    Text("Aliquot Jar")
                } footer: {
                    Text("Optional — log estimated dough rise percentage if using an aliquot jar.")
                }

                Section {
                    ProgressView(value: progress) {
                        HStack {
                            Text("Degree-hours")
                            Spacer()
                            Text(String(format: "%.1f / %.0f", currentDegreeHours, targetDegreeHours))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let remaining = estimatedMinutesRemaining, remaining > 0 {
                        HStack {
                            Label("Estimated remaining", systemImage: "clock")
                            Spacer()
                            Text(formatMinutes(remaining))
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    } else if progress >= 1.0 {
                        Label("Bulk ferment target reached!", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                } header: {
                    Text("Fermentation Progress")
                }
            }
            .navigationTitle("Log Temperature")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveReading()
                        dismiss()
                    }
                }
            }
        }
    }

    private func saveReading() {
        let sequenceNumber = existingReadings.count

        // Calculate degree-hours including this new reading
        var allPairs = existingReadings.map {
            (timestamp: $0.timestamp, temperatureCelsius: $0.temperatureCelsius)
        }
        allPairs.append((timestamp: Date(), temperatureCelsius: temperatureCelsius))
        let accumulated = DegreeHourCalculator.accumulatedDegreeHours(readings: allPairs)

        let rise = Double(aliquotRisePercent)

        let reading = DoughTemperatureReading(
            timestamp: Date(),
            temperatureCelsius: temperatureCelsius,
            sequenceNumber: sequenceNumber,
            accumulatedDegreeHours: accumulated,
            associatedStepTypeID: foldStep.map { StepTypeID(rawValue: $0.stepTypeID) } ?? nil,
            aliquotRisePercent: rise
        )
        reading.schedule = schedule
        modelContext.insert(reading)
    }

    private func formatMinutes(_ minutes: Double) -> String {
        let m = Int(minutes)
        if m >= 60 {
            return "\(m / 60)h \(m % 60)m"
        }
        return "\(m)m"
    }
}
