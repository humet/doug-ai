import SwiftUI

struct ConflictOption: Identifiable {
    let id = UUID()
    let summary: String
    let explanation: String
    let targetTimeShiftMinutes: Double?

    init(
        summary: String,
        explanation: String,
        targetTimeShiftMinutes: Double? = nil
    ) {
        self.summary = summary
        self.explanation = explanation
        self.targetTimeShiftMinutes = targetTimeShiftMinutes
    }
}

struct ConflictResolutionSheet: View {
    let conflict: ScheduleConflict
    let recipe: Recipe
    let kitchenTemp: Double
    let onOptionSelected: (ConflictOption) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var options: [ConflictOption] = []
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label(conflict.message, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                } header: {
                    Text("Conflict")
                }

                if isLoading {
                    Section {
                        HStack {
                            Spacer()
                            ProgressView("Finding alternatives...")
                            Spacer()
                        }
                    }
                } else {
                    Section {
                        ForEach(options) { option in
                            Button {
                                onOptionSelected(option)
                                dismiss()
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(option.summary)
                                        .font(.subheadline.bold())
                                        .foregroundStyle(.primary)
                                    Text(option.explanation)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    } header: {
                        Text("Options")
                    }
                }
            }
            .navigationTitle("Schedule Conflict")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task {
                await loadOptions()
            }
        }
    }

    private func loadOptions() async {
        options = generateFallbackOptions()
        isLoading = false
    }

    private func generateFallbackOptions() -> [ConflictOption] {
        var fallback: [ConflictOption] = []

        if let altTime = conflict.suggestedAlternativeTime {
            let formatted = altTime.formatted(date: .omitted, time: .shortened)
            fallback.append(ConflictOption(
                summary: "Move \(conflict.conflictingStepLabel) to \(formatted)",
                explanation: "Shifts the step to avoid the conflict."
            ))
        }

        fallback.append(ConflictOption(
            summary: "Choose a different bread-ready time",
            explanation: "A different target time may avoid the conflict entirely."
        ))

        return fallback
    }
}
