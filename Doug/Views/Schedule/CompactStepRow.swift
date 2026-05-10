import SwiftUI

/// Trimmed upcoming-step row: icon, label, clock start time, chevron.
/// Tapping opens the full `StepDetailSheet`.
struct CompactStepRow: View {
    let step: ScheduleStep
    let referenceDate: Date
    var isSubStep: Bool = false
    var hasConflict: Bool = false
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                statusDot
                StepTypeIconView(stepTypeID: stepTypeIDEnum, size: isSubStep ? 14 : 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(step.stepType.label)
                        .font(isSubStep ? .caption.weight(.medium) : .subheadline.weight(.medium))
                    StepCountdownLabel(step: step, referenceDate: referenceDate)
                }
                Spacer()
                if hasConflict {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Text(step.computedStartTime, style: .time)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(hasConflict ? .orange : .secondary)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                hasConflict
                    ? Color.orange.opacity(0.08)
                    : DougTheme.cardBackground,
                in: .rect(cornerRadius: 12)
            )
        }
        .buttonStyle(.plain)
        .padding(.leading, isSubStep ? 24 : 0)
    }

    private var stepTypeIDEnum: StepTypeID {
        StepTypeID(rawValue: step.stepTypeID) ?? .mix
    }

    private var statusDot: some View {
        Circle()
            .fill(statusColor)
            .frame(width: 8, height: 8)
    }

    private var statusColor: Color {
        switch step.stepStatus {
        case .upcoming: DougTheme.stepUpcoming
        case .active: DougTheme.stepActive
        case .done: DougTheme.stepDone
        case .skipped: DougTheme.stepSkipped
        }
    }
}
