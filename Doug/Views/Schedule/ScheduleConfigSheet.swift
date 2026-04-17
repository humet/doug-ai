import SwiftData
import SwiftUI

struct ScheduleConfigSheet: View {
    @Bindable var viewModel: ScheduleViewModel
    let onStartBake: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Query private var availabilities: [UserAvailability]
    @Query private var windows: [UnavailableWindow]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Label(viewModel.selectedRecipe.name, systemImage: "book")
                            .font(.headline)
                        Spacer()
                        Text("\(viewModel.selectedRecipe.hydrationPercent)%")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Recipe")
                }

                Section {
                    DatePicker(
                        "Bread ready by",
                        selection: $viewModel.targetDate,
                        in: Date()...,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                } header: {
                    Text("Target Time")
                }

                Section {
                    HStack {
                        Text("Kitchen temperature")
                        Spacer()
                        Text("\(Int(viewModel.kitchenTemperature))°C")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Slider(
                        value: $viewModel.kitchenTemperature,
                        in: 16 ... 32,
                        step: 1
                    ) {
                        Text("Temperature")
                    }
                    .onChange(of: viewModel.kitchenTemperature) {
                        viewModel.buildPreview(
                            availability: availabilities.first,
                            windows: Array(windows)
                        )
                    }
                } header: {
                    Text("Temperature")
                }

                if !viewModel.previewSteps.isEmpty {
                    Section {
                        ForEach(viewModel.previewSteps) { step in
                            PreviewStepRow(step: step)
                        }
                    } header: {
                        Text("Schedule Preview")
                    }
                }

                if let conflict = viewModel.conflict {
                    Section {
                        Label(conflict.message, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    } header: {
                        Text("Conflict")
                    }
                }
            }
            .navigationTitle("Plan Your Bake")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start Bake") {
                        onStartBake()
                    }
                    .disabled(viewModel.previewSteps.isEmpty)
                }
            }
            .onAppear {
                viewModel.buildPreview(
                    availability: availabilities.first,
                    windows: Array(windows)
                )
            }
            .onChange(of: viewModel.targetDate) {
                viewModel.buildPreview(
                    availability: availabilities.first,
                    windows: Array(windows)
                )
            }
        }
    }
}

private struct PreviewStepRow: View {
    let step: ScheduledStep

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(step.label)
                    .font(.subheadline)
                Text(step.startTime, style: .time)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Spacer()

            Text(formattedDuration)
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()

            classificationBadge
        }
    }

    private var formattedDuration: String {
        let minutes = Int(step.durationMinutes)
        if minutes >= 60 {
            let hours = minutes / 60
            let mins = minutes % 60
            return mins > 0 ? "\(hours)h \(mins)m" : "\(hours)h"
        }
        return "\(minutes)m"
    }

    @ViewBuilder
    private var classificationBadge: some View {
        switch step.classification {
        case .handsOn:
            Image(systemName: "hand.raised")
                .font(.caption2)
                .foregroundStyle(.blue)
        case .passiveFlexible:
            Image(systemName: "arrow.left.and.right")
                .font(.caption2)
                .foregroundStyle(.green)
        case .passiveFixed:
            Image(systemName: "clock")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
