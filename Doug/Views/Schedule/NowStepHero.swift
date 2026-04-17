import SwiftData
import SwiftUI

/// Prominent hero card for the currently-active (or most-imminent upcoming) step.
/// Shows icon, label, live countdown, instructions, success signal, and the common-case
/// inline controls: Mark Done / Finish Early / Add Time / Pause. Full controls live in
/// `StepDetailSheet`, reached via the "Step details…" menu item.
struct NowStepHero: View {
    let step: ScheduleStep
    let viewModel: ScheduleViewModel
    let referenceDate: Date
    let onOpenDetail: (ScheduleStep) -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var showTemperatureEntry = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Text(step.stepType.instructionText)
                .font(.subheadline)

            if !step.stepType.successSignal.isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "checkmark.seal")
                        .font(.caption)
                        .foregroundStyle(.green)
                    Text(step.stepType.successSignal)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            primaryActions
            secondaryActions
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(accentTint.opacity(0.35), lineWidth: 1.5)
        )
        .sheet(isPresented: $showTemperatureEntry) {
            if let schedule = step.schedule {
                TemperatureEntryView(schedule: schedule, foldStep: step)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            StepTypeIconView(stepTypeID: stepTypeIDEnum, size: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(eyebrow)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(accentTint)
                Text(step.stepType.label)
                    .font(.title2.bold())
                StepCountdownLabel(step: step, referenceDate: referenceDate)
                    .font(.subheadline.monospacedDigit())
            }
            Spacer()
            Menu {
                Button {
                    onOpenDetail(step)
                } label: {
                    Label("Step details…", systemImage: "text.alignleft")
                }
                if step.stepStatus == .active || step.stepStatus == .upcoming {
                    Button {
                        viewModel.extendStep(step, byMinutes: 15, modelContext: modelContext)
                    } label: {
                        Label("Add 15m", systemImage: "plus")
                    }
                    Button {
                        viewModel.extendStep(step, byMinutes: 30, modelContext: modelContext)
                    } label: {
                        Label("Add 30m", systemImage: "plus")
                    }
                }
                if step.stepStatus == .upcoming, Date() > step.computedStartTime {
                    Button {
                        viewModel.startStepNow(step, modelContext: modelContext)
                    } label: {
                        Label("Set start to now", systemImage: "clock.arrow.circlepath")
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .padding(6)
                    .contentShape(.rect)
            }
        }
    }

    // MARK: - Primary actions

    private var primaryActions: some View {
        HStack(spacing: 10) {
            if step.stepType.requiresTempReading, step.stepStatus == .active {
                Button {
                    showTemperatureEntry = true
                } label: {
                    Label("Enter Temp", systemImage: "thermometer.medium")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .adaptiveGlassButtonStyle(prominent: true)
            } else if showsMarkDone {
                Button {
                    viewModel.markStepDone(step, modelContext: modelContext)
                } label: {
                    Label("Mark Done", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .adaptiveGlassButtonStyle(prominent: true)
            } else if showsFinishEarly {
                Button {
                    viewModel.finishStepEarly(step, modelContext: modelContext)
                } label: {
                    Label("Finish Early", systemImage: "checkmark")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .adaptiveGlassButtonStyle(prominent: true)
            }
        }
    }

    // MARK: - Secondary actions

    private var secondaryActions: some View {
        HStack(spacing: 10) {
            Button {
                viewModel.extendStep(step, byMinutes: 15, modelContext: modelContext)
            } label: {
                Label("+15m", systemImage: "plus.circle")
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .adaptiveGlassButtonStyle()

            Button {
                if isPaused {
                    viewModel.resumeSchedule(modelContext: modelContext)
                } else {
                    viewModel.pauseSchedule(modelContext: modelContext)
                }
            } label: {
                Label(
                    isPaused ? "Resume" : "Pause",
                    systemImage: isPaused ? "play.fill" : "pause.fill"
                )
                .font(.caption.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .adaptiveGlassButtonStyle()
        }
    }

    // MARK: - Derived

    private var stepTypeIDEnum: StepTypeID {
        StepTypeID(rawValue: step.stepTypeID) ?? .mix
    }

    private var eyebrow: String {
        switch step.stepStatus {
        case .active: "Now"
        case .upcoming: "Up next"
        case .done: "Completed"
        case .skipped: "Skipped"
        }
    }

    private var accentTint: Color {
        StepTypeIcon.tint(for: stepTypeIDEnum)
    }

    private var showsMarkDone: Bool {
        step.stepStatus == .active && step.stepType.classification == .handsOn
    }

    private var showsFinishEarly: Bool {
        step.stepStatus == .active
            && step.stepType.classification != .handsOn
            && Date() < step.computedEndTime
    }

    private var isPaused: Bool {
        step.schedule?.pausedAt != nil
    }
}
