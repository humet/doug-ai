import SwiftUI

struct ColdRetardSliderView: View {
    let coldRetardStep: ScheduleStep
    let flexRange: ClosedRange<Double>
    let onAdjust: (Double) -> Void

    @State private var durationMinutes: Double
    @Environment(\.dismiss) private var dismiss

    init(
        coldRetardStep: ScheduleStep,
        flexRange: ClosedRange<Double>,
        onAdjust: @escaping (Double) -> Void
    ) {
        self.coldRetardStep = coldRetardStep
        self.flexRange = flexRange
        self.onAdjust = onAdjust
        _durationMinutes = State(initialValue: coldRetardStep.computedDurationMinutes)
    }

    private var durationHours: Double {
        durationMinutes / 60
    }

    private var newEndTime: Date {
        coldRetardStep.computedStartTime.addingTimeInterval(durationMinutes * 60)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Cold retard duration")
                            Spacer()
                            Text(String(format: "%.1fh", durationHours))
                                .font(.title3.bold().monospacedDigit())
                        }

                        Slider(
                            value: $durationMinutes,
                            in: flexRange,
                            step: 30
                        ) {
                            Text("Duration")
                        }
                        .accessibilityLabel("Cold retard duration")
                        .accessibilityValue("\(Int(durationHours)) hours")

                        HStack {
                            Text(String(format: "%.0fh", flexRange.lowerBound / 60))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(String(format: "%.0fh", flexRange.upperBound / 60))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Adjust Duration")
                }

                Section {
                    HStack {
                        Text("Into fridge")
                        Spacer()
                        Text(coldRetardStep.computedStartTime, style: .time)
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Out of fridge")
                        Spacer()
                        Text(newEndTime, style: .time)
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Bread ready")
                        Spacer()
                        // Preheat (60m) + bake covered (~20m) + bake uncovered (~25m)
                        Text(newEndTime.addingTimeInterval(105 * 60), style: .time)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Updated Timeline")
                }

                Section {
                    flavourNote
                } header: {
                    Text("Flavour Impact")
                }
            }
            .navigationTitle("Life Happened")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        onAdjust(durationMinutes)
                        dismiss()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var flavourNote: some View {
        if durationHours < 10 {
            Label("Shorter retard — milder, less sour flavour.", systemImage: "leaf")
                .font(.subheadline)
        } else if durationHours < 14 {
            Label("Balanced retard — moderate tang, good complexity.", systemImage: "leaf.fill")
                .font(.subheadline)
        } else {
            Label("Long retard — more sour, deeper flavour development.", systemImage: "flame")
                .font(.subheadline)
        }
    }
}
