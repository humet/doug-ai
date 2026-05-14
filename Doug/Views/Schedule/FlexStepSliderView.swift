import SwiftUI

struct FlexStepSliderView: View {
    let step: ScheduleStep
    let flexRange: ClosedRange<Double>
    let remainingMinutesAfterStep: Double
    let completionLabel: String
    let onAdjust: (Double) -> Void

    @State private var durationMinutes: Double
    @Environment(\.dismiss) private var dismiss

    init(
        step: ScheduleStep,
        flexRange: ClosedRange<Double>,
        remainingMinutesAfterStep: Double,
        completionLabel: String = "Bread Ready",
        onAdjust: @escaping (Double) -> Void
    ) {
        self.step = step
        self.flexRange = flexRange
        self.remainingMinutesAfterStep = remainingMinutesAfterStep
        self.completionLabel = completionLabel
        self.onAdjust = onAdjust
        _durationMinutes = State(initialValue: step.computedDurationMinutes)
    }

    private var stepTypeID: StepTypeID? {
        StepTypeID(rawValue: step.stepTypeID)
    }

    private var isColdRetard: Bool {
        stepTypeID == .coldRetard
    }

    private var durationHours: Double {
        durationMinutes / 60
    }

    private var newEndTime: Date {
        step.computedStartTime.addingTimeInterval(durationMinutes * 60)
    }

    private var stepLabel: String {
        stepTypeID.map { StepTypeRegistry.type(for: $0).label } ?? "Step"
    }

    private var sliderStep: Double {
        isColdRetard ? 30 : 15
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("\(stepLabel) duration")
                            Spacer()
                            Text(String(format: "%.1fh", durationHours))
                                .font(.title3.bold().monospacedDigit())
                        }

                        Slider(
                            value: $durationMinutes,
                            in: flexRange,
                            step: sliderStep
                        ) {
                            Text("Duration")
                        }
                        .accessibilityLabel("\(stepLabel) duration")
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
                        Text(isColdRetard ? "Into fridge" : "Starts")
                        Spacer()
                        Text(step.computedStartTime, style: .time)
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text(isColdRetard ? "Out of fridge" : "Ends")
                        Spacer()
                        Text(newEndTime, style: .time)
                            .foregroundStyle(.secondary)
                    }
                    if remainingMinutesAfterStep > 0 {
                        HStack {
                            Text(completionLabel)
                            Spacer()
                            Text(newEndTime.addingTimeInterval(remainingMinutesAfterStep * 60), style: .time)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Updated Timeline")
                }

                Section {
                    impactNote
                } header: {
                    Text(isColdRetard ? "Flavour Impact" : "Proofing Note")
                }
            }
            .navigationTitle("Adjust Timing")
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
    private var impactNote: some View {
        if isColdRetard {
            coldRetardNote
        } else if stepTypeID == .finalProof {
            finalProofNote
        } else {
            Label("Adjust within the allowed range to fit your schedule.", systemImage: "clock")
                .font(.subheadline)
        }
    }

    @ViewBuilder
    private var coldRetardNote: some View {
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

    @ViewBuilder
    private var finalProofNote: some View {
        if durationMinutes < 75 {
            Label("Short proof — may be slightly under-proofed. Watch the poke test.", systemImage: "exclamationmark.triangle")
                .font(.subheadline)
        } else if durationMinutes <= 120 {
            Label("Good proof window — expect a well-risen, airy crumb.", systemImage: "leaf.fill")
                .font(.subheadline)
        } else {
            Label("Long proof — risk of over-proofing in a warm kitchen. Bake promptly.", systemImage: "exclamationmark.triangle")
                .font(.subheadline)
        }
    }
}
