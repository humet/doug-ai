import SwiftUI

struct SlotExplainerSheet: View {
    let slot: TimeSlot
    let recipeName: String

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                switch slot.viability {
                case .available:
                    Section {
                        Label("This time works with no issues.", systemImage: "checkmark.circle")
                            .foregroundStyle(.green)
                    }

                case let .flexed(details):
                    Section {
                        Label("This time works, but some steps are shortened.", systemImage: "arrow.left.and.right")
                            .foregroundStyle(.orange)
                    } header: {
                        Text("Tight Fit")
                    }

                    Section {
                        ForEach(Array(details.enumerated()), id: \.offset) { _, detail in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(detail.stepLabel)
                                    .font(.subheadline.bold())
                                Text("\(formattedDuration(detail.actualDurationMinutes)) instead of the usual \(formattedDuration(detail.defaultDurationMinutes))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } header: {
                        Text("Adjusted Steps")
                    }

                case let .conflict(conflict):
                    Section {
                        Label(conflict.message, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    } header: {
                        Text("Conflict")
                    }

                    Section {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 6) {
                                Image(systemName: "hand.raised")
                                    .foregroundStyle(.blue)
                                    .font(.caption)
                                Text(conflict.conflictingStepLabel)
                                    .font(.subheadline.bold())
                            }

                            if let start = conflict.conflictingWindowStart,
                               let end = conflict.conflictingWindowEnd
                            {
                                HStack(spacing: 6) {
                                    Image(systemName: "calendar.badge.clock")
                                        .foregroundStyle(.red)
                                        .font(.caption)
                                    Text("\(conflict.conflictingWindowName): \(start, style: .time) – \(end, style: .time)")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            } else {
                                HStack(spacing: 6) {
                                    Image(systemName: "moon.zzz")
                                        .foregroundStyle(.secondary)
                                        .font(.caption)
                                    Text("Outside \(conflict.conflictingWindowName)")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    } header: {
                        Text("Details")
                    }
                }
            }
            .navigationTitle("Why This Time?")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func formattedDuration(_ minutes: Double) -> String {
        let m = Int(minutes)
        if m >= 60 {
            let h = m / 60
            let rem = m % 60
            return rem > 0 ? "\(h)h \(rem)m" : "\(h)h"
        }
        return "\(m)m"
    }
}
