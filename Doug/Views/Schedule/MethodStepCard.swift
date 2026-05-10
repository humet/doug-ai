import SwiftUI

/// A single row in the pre-bake method overview — icon, label, duration, classification, instructions.
/// Renders sub-steps (e.g. folds under bulk ferment) inline in a compact form.
struct MethodStepCard: View {
    let step: MethodStep
    let stepNumber: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Text(step.stepType.instructionText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(step.stepType.successSignal)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, 10)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(StepTypeIcon.tint(for: step.stepTypeID).opacity(0.4))
                        .frame(width: 2)
                }

            if let foldCount = step.foldCount, foldCount > 0 {
                Text(
                    "Includes \(foldCount) stretch & folds spaced across the first \(Int((step.foldSpacingFraction ?? 0.67) * 100))% of this step."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DougTheme.cardBackground, in: .rect(cornerRadius: 14))
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            StepTypeIconView(stepTypeID: step.stepTypeID, size: 22)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text("Step \(stepNumber)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    classificationChip
                }
                Text(step.stepType.label)
                    .font(.headline)
            }
            Spacer()
            Text(durationText)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var classificationChip: some View {
        let (label, color): (String, Color) = switch step.stepType.classification {
        case .handsOn: ("Hands-on", .blue)
        case .passiveFlexible: ("Flexible", .green)
        case .passiveFixed: ("Passive", .secondary)
        }
        Text(label)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(color)
            .background(color.opacity(0.15), in: .capsule)
    }

    private var durationText: String {
        if let range = step.effectiveFlexRange {
            let lower = Int(range.lowerBound)
            let upper = Int(range.upperBound)
            return formatMinutes(lower) + "–" + formatMinutes(upper)
        }
        return formatMinutes(Int(step.effectiveDuration))
    }

    private func formatMinutes(_ minutes: Int) -> String {
        if minutes >= 60 {
            let hours = minutes / 60
            let mins = minutes % 60
            return mins > 0 ? "\(hours)h \(mins)m" : "\(hours)h"
        }
        return "\(minutes)m"
    }
}
