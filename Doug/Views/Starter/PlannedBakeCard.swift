import SwiftData
import SwiftUI

/// Connects the Starter tab to a planned or in-flight bake: which recipe, when
/// the bread is ready, and which starter step the schedule is waiting on. Tap
/// to jump to the Schedule tab.
struct PlannedBakeCard: View {
    let schedule: Schedule

    /// Step types the Starter tab's own actions can satisfy.
    private static let starterStepTypeIDs: Set<String> = [
        StepTypeID.activateStarter.rawValue,
        StepTypeID.waitForPeak.rawValue,
        StepTypeID.buildLevain.rawValue,
        StepTypeID.waitForLevainPeak.rawValue,
    ]

    private var nextStarterStep: ScheduleStep? {
        schedule.steps
            .filter { $0.parentStep == nil }
            .sorted { $0.sequenceIndex < $1.sequenceIndex }
            .first {
                Self.starterStepTypeIDs.contains($0.stepTypeID)
                    && ($0.stepStatus == .upcoming || $0.stepStatus == .active)
            }
    }

    var body: some View {
        Section {
            Button {
                NotificationRouter.shared.selectedTab = .schedule
            } label: {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        Image(systemName: "calendar.badge.clock")
                            .font(.title3)
                            .foregroundStyle(.orange)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(schedule.recipe.name)
                                .font(.subheadline.bold())
                            let readyAt = schedule.targetBreadReadyTime
                                .formatted(.dateTime.weekday(.wide).hour().minute())
                            Text("Bread ready \(readyAt)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }

                    if let step = nextStarterStep {
                        let startAt = step.computedStartTime.formatted(.dateTime.hour().minute())
                        Text("Next for this bake: \(step.stepType.label) at \(startAt)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)
        } header: {
            Text(schedule.scheduleStatus == .active ? "Bake in Progress" : "Planned Bake")
        } footer: {
            if nextStarterStep != nil {
                Text("Starter actions you log here count toward the schedule automatically.")
            }
        }
    }
}
