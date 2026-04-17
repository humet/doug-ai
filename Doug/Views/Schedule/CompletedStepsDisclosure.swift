import SwiftUI

/// Pill summary of completed / skipped steps that expands to show the rows inline.
/// Rows tap into `StepDetailSheet` via the `onSelect` closure so the user can reopen.
struct CompletedStepsDisclosure: View {
    let completedSteps: [ScheduleStep]
    let referenceDate: Date
    let onSelect: (ScheduleStep) -> Void

    @State private var expanded = false

    var body: some View {
        if completedSteps.isEmpty {
            EmptyView()
        } else {
            VStack(spacing: 8) {
                Button {
                    withAnimation(.smooth(duration: 0.25)) {
                        expanded.toggle()
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(DougTheme.stepDone)
                        Text("\(completedSteps.count) completed")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(expanded ? 180 : 0))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 12))
                }
                .buttonStyle(.plain)

                if expanded {
                    VStack(spacing: 4) {
                        ForEach(completedSteps) { step in
                            Button {
                                onSelect(step)
                            } label: {
                                completedRow(step)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }

    private func completedRow(_ step: ScheduleStep) -> some View {
        HStack(spacing: 10) {
            StepTypeIconView(stepTypeID: StepTypeID(rawValue: step.stepTypeID) ?? .mix, size: 14)
            Text(step.stepType.label)
                .font(.caption.weight(.medium))
            Spacer()
            StepCountdownLabel(step: step, referenceDate: referenceDate)
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.tertiarySystemBackground), in: .rect(cornerRadius: 10))
    }
}
