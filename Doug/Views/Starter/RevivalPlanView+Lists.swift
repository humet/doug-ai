import SwiftUI

/// The plan view's supporting lists: what's already done, and what's still
/// to come. Split out to keep the main view focused on the current step.
extension RevivalPlanView {
    @ViewBuilder
    var completedStepsSection: some View {
        let completed = sortedSteps.filter { $0.feedStatus == .completed }
        if !completed.isEmpty {
            Section {
                ForEach(completed) { step in
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text(step.instructionTitle ?? "Feed \(step.sequenceIndex + 1)")
                            .font(.subheadline)
                        Spacer()
                        Text(peakDurationLabel(step))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    var upcomingStepsSection: some View {
        let skipThrough = currentStep?.feedStatus == .peaked
            ? plan.currentStepIndex + 1
            : plan.currentStepIndex
        let pending = sortedSteps.filter { $0.sequenceIndex > skipThrough }
        if !pending.isEmpty, plan.revivalStatus == .active {
            Section {
                ForEach(pending) { step in
                    upcomingRow(step)
                }
            } header: {
                Text("Upcoming")
            }
        }
    }

    func upcomingRow(_ step: RevivalFeedStep) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text("Feed \(step.sequenceIndex + 1)")
                    .font(.subheadline.bold())
                Spacer()
                Text(step.scheduledTime, format: .dateTime.weekday(.abbreviated).hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let original = step.originalScheduledTime,
               abs(original.timeIntervalSince(step.scheduledTime)) > 60
            {
                Text("Shifted from \(original, format: .dateTime.hour().minute())")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }

            if let retain = step.retainStarterGrams,
               let flour = step.addFlourGrams,
               let water = step.addWaterGrams
            {
                Text(
                    "Retain \(Int(retain.rounded())) g · +\(Int(flour.rounded())) g flour · +\(Int(water.rounded())) g water"
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
    }
}
