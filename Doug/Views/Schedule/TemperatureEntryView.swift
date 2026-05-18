import SwiftData
import SwiftUI

/// View for logging dough temperature at each fold during an active bake.
///
/// Deep-linked from fold notifications. Shows current fold context,
/// temperature input, and accumulated degree-hour progress.
struct TemperatureEntryView: View {
    let schedule: Schedule
    let foldStep: ScheduleStep?
    var onSave: (() -> Void)?
    var onSkip: (() -> Void)?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var temperatureCelsius: Double = 24.0

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
                    } else {
                        Label("Bulk Ferment", systemImage: "clock.arrow.2.circlepath")
                            .font(.headline)
                        Text("Log your current dough temperature to track fermentation progress.")
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
                    Slider(value: $temperatureCelsius, in: 18 ... 35, step: 0.5)
                        .accessibilityLabel("Dough temperature")
                        .accessibilityValue(String(format: "%.1f degrees", temperatureCelsius))
                } header: {
                    Text("Temperature Reading")
                }

                Section {
                    ProgressView(value: progress) {
                        HStack {
                            Text("Fermentation progress")
                            Spacer()
                            Text(String(format: "%.0f%%", min(progress * 100, 100)))
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
            .navigationTitle(onSkip != nil ? "Log Temperature?" : "Log Temperature")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if onSkip != nil {
                        Button("Skip") {
                            onSkip?()
                            dismiss()
                        }
                    } else {
                        Button("Cancel") { dismiss() }
                    }
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

        let reading = DoughTemperatureReading(
            timestamp: Date(),
            temperatureCelsius: temperatureCelsius,
            sequenceNumber: sequenceNumber,
            accumulatedDegreeHours: accumulated,
            associatedStepTypeID: foldStep.map { StepTypeID(rawValue: $0.stepTypeID) } ?? nil
        )
        reading.schedule = schedule
        modelContext.insert(reading)

        onSave?()
    }

    private func formatMinutes(_ minutes: Double) -> String {
        let m = Int(minutes)
        if m >= 60 {
            return "\(m / 60)h \(m % 60)m"
        }
        return "\(m)m"
    }
}
