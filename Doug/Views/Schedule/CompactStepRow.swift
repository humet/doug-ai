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
                    if let summary = levainBuildSummary {
                        Text(summary)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if hasConflict {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                if let temp = ovenTemperature {
                    Label("\(temp)°", systemImage: "flame.fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.orange)
                }
                DayTimeLabel(date: step.computedStartTime)
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

    private var ovenTemperature: Int? {
        guard [.preheat, .bakeCovered, .bakeUncovered].contains(stepTypeIDEnum) else { return nil }
        return step.schedule?.recipe.bakeTemperature(for: stepTypeIDEnum)
    }

    /// One-line measurements for an upcoming Build Levain step, so the amounts
    /// are visible before the step opens.
    private var levainBuildSummary: String? {
        guard stepTypeIDEnum == .buildLevain,
              step.stepStatus == .upcoming,
              let schedule = step.schedule else { return nil }
        // Prefer the scheduler's adaptively-chosen ratio (e.g. a slow overnight
        // build) over the recipe's fixed default.
        let adaptive = step.levainRatioBucket
        let build = LevainBuildCalculator.calculate(.init(
            levainGramsNeeded: schedule.scaledIngredients.levainGrams,
            baseRatio: adaptive?.buildRatio ?? schedule.recipe.levainBuildRatio,
            referenceTemp: schedule.recipe.referenceTemperatureCelsius,
            kitchenTemp: schedule.kitchenTemperatureCelsius
        ))
        let amounts = "\(Int(build.starterGrams))g starter + \(Int(build.flourGrams))g flour + \(Int(build.waterGrams))g water"
        if let label = adaptive?.adaptiveBuildLabel {
            return "\(label) · \(amounts)"
        }
        return amounts
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
