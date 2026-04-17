import SwiftData
import SwiftUI

/// Slim banner shown in the active schedule header when `schedule.pausedAt != nil`.
/// Offers a one-tap Resume that pushes downstream steps by the elapsed pause duration.
struct PausedBanner: View {
    let pausedAt: Date
    let viewModel: ScheduleViewModel
    let referenceDate: Date

    @Environment(\.modelContext) private var modelContext

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "pause.circle.fill")
                .font(.title3)
                .foregroundStyle(.indigo)

            VStack(alignment: .leading, spacing: 2) {
                Text("Bake paused")
                    .font(.subheadline.weight(.semibold))
                Text("Paused \(StepCountdownLabel.format(seconds: elapsed)) ago")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Spacer()

            Button("Resume") {
                viewModel.resumeSchedule(modelContext: modelContext)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding()
        .background(Color.indigo.opacity(0.12), in: .rect(cornerRadius: 14))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Bake is paused")
        .accessibilityAction(named: "Resume") {
            viewModel.resumeSchedule(modelContext: modelContext)
        }
    }

    private var elapsed: TimeInterval {
        max(0, referenceDate.timeIntervalSince(pausedAt))
    }
}
