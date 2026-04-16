import SwiftUI
import SwiftData

/// Shows the active revival plan with progress through planned feeds.
struct RevivalPlanView: View {
    let plan: RevivalPlan

    @Environment(\.modelContext) private var modelContext

    var body: some View {
        List {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Revival Plan")
                            .font(.headline)
                        Text("Started \(plan.startDate, style: .relative)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    statusBadge
                }

                if let bakeReady = plan.estimatedBakeReadyDate {
                    HStack {
                        Label("Estimated bake-ready", systemImage: "calendar")
                        Spacer()
                        Text(bakeReady, format: .dateTime.weekday(.wide).hour().minute())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                ForEach(sortedSteps) { step in
                    RevivalFeedStepRow(step: step) {
                        markComplete(step)
                    }
                }
            } header: {
                Text("Feeds")
            } footer: {
                Text("Complete each feed and log time-to-peak. Once peak times normalize, your starter is bake-ready.")
            }

            if plan.revivalStatus == .active {
                Section {
                    Button("Cancel Revival", role: .destructive) {
                        plan.revivalStatus = .cancelled
                    }
                }
            }
        }
        .navigationTitle("Revival Plan")
    }

    private var sortedSteps: [RevivalFeedStep] {
        plan.feedSteps.sorted { $0.sequenceIndex < $1.sequenceIndex }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch plan.revivalStatus {
        case .active:
            Text("Active")
                .font(.caption.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(.orange, in: .capsule)
        case .completed:
            Text("Complete")
                .font(.caption.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(.green, in: .capsule)
        case .cancelled:
            Text("Cancelled")
                .font(.caption.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(.secondary, in: .capsule)
        }
    }

    private func markComplete(_ step: RevivalFeedStep) {
        step.feedStatus = .completed

        // Check if all steps are done
        if sortedSteps.allSatisfy({ $0.feedStatus == .completed }) {
            plan.revivalStatus = .completed
        }
    }
}

private struct RevivalFeedStepRow: View {
    let step: RevivalFeedStep
    let onComplete: () -> Void

    var body: some View {
        HStack {
            Image(systemName: step.feedStatus == .completed ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(step.feedStatus == .completed ? .green : .secondary)
                .font(.title3)

            VStack(alignment: .leading, spacing: 4) {
                Text("Feed \(step.sequenceIndex + 1)")
                    .font(.subheadline.bold())
                Text("\(step.targetRatioStarter):\(step.targetRatioFlour):\(step.targetRatioWater)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(step.scheduledTime, format: .dateTime.weekday(.abbreviated).hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if step.feedStatus == .pending {
                Button("Done", action: onComplete)
                    .buttonStyle(.bordered)
                    .font(.caption)
            } else {
                Text("Expected peak: \(Int(step.expectedPeakMinutes))m")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
