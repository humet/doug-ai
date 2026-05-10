import SwiftData
import SwiftUI

/// Full-controls sheet for a `ScheduleStep`. Renders a mode-aware detail view:
/// - Upcoming: instructions + adjustment controls
/// - Active: instructions + Done + temp-entry handoff + controls
/// - Done / Skipped: summary + Go Back (if it's the most-recent)
struct StepDetailSheet: View {
    let step: ScheduleStep
    let viewModel: ScheduleViewModel
    let isMostRecentlyCompleted: Bool

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var showTemperatureEntry = false

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        header(now: context.date)
                        instructions
                        if step.stepStatus == .active, step.stepType.requiresTempReading {
                            temperatureEntryButton
                        }
                        if showsMarkDoneButton {
                            markDoneButton
                        }
                        if step.stepStatus == .done || step.stepStatus == .skipped {
                            if isMostRecentlyCompleted {
                                reopenButton
                            }
                            historyBlock
                        } else if step.stepStatus == .active {
                            StepAdjustmentControls(
                                step: step,
                                viewModel: viewModel,
                                onAction: { dismiss() }
                            )
                        }
                    }
                    .padding()
                }
            }
            .background(DougTheme.warmCream)
            .navigationTitle(step.stepType.label)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .sheet(isPresented: $showTemperatureEntry) {
            if let schedule = step.schedule {
                TemperatureEntryView(schedule: schedule, foldStep: step)
            }
        }
    }

    // MARK: - Header

    private func header(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                StepTypeIconView(stepTypeID: stepTypeIDEnum, size: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(step.stepType.label)
                        .font(.title3.bold())
                    StepCountdownLabel(step: step, referenceDate: now)
                }
                Spacer()
                statusBadge
            }

            HStack(spacing: 16) {
                scheduledTime(label: "Start", time: step.computedStartTime)
                scheduledTime(label: "End", time: step.computedEndTime)
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
        .padding()
        .background(DougTheme.cardBackground, in: .rect(cornerRadius: 16))
    }

    private var statusBadge: some View {
        let (label, color): (String, Color) = switch step.stepStatus {
        case .upcoming: ("Upcoming", DougTheme.stepUpcoming)
        case .active: ("Active", DougTheme.stepActive)
        case .done: ("Done", DougTheme.stepDone)
        case .skipped: ("Skipped", DougTheme.stepSkipped)
        }
        return Text(label)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color, in: .capsule)
    }

    private func scheduledTime(label: String, time: Date) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(time, style: .time)
        }
    }

    // MARK: - Instructions

    private var instructions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("What to do")
                .font(.subheadline.bold())
            Text(step.stepType.instructionText)
                .font(.subheadline)
            Text("You'll know it's done when")
                .font(.subheadline.bold())
                .padding(.top, 8)
            Text(step.stepType.successSignal)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(DougTheme.cardBackground, in: .rect(cornerRadius: 14))
    }

    // MARK: - Primary actions

    private var temperatureEntryButton: some View {
        Button {
            showTemperatureEntry = true
        } label: {
            Label("Enter Temperature", systemImage: "thermometer.medium")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
        }
        .adaptiveGlassButtonStyle(prominent: true)
    }

    private var markDoneButton: some View {
        Button {
            viewModel.markStepDone(step, modelContext: modelContext)
            dismiss()
        } label: {
            Label("Done", systemImage: "checkmark.circle.fill")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
        }
        .adaptiveGlassButtonStyle(prominent: true)
    }

    private var reopenButton: some View {
        Button {
            viewModel.reopenStep(step, modelContext: modelContext)
            dismiss()
        } label: {
            Label("Go Back to This Step", systemImage: "arrow.uturn.backward.circle")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
        }
        .adaptiveGlassButtonStyle()
    }

    // MARK: - History block (done / skipped)

    private var historyBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let actualEnd = step.actualEndTime {
                Label {
                    Text("Finished at \(actualEnd, style: .time)")
                } icon: {
                    Image(systemName: "checkmark.circle")
                        .foregroundStyle(.green)
                }
            }
            let readings = (step.schedule?.temperatureReadings ?? []).filter {
                $0.associatedStepTypeID == step.stepTypeID
            }
            if !readings.isEmpty {
                let latest = readings.sorted { $0.timestamp < $1.timestamp }.last!
                Label {
                    Text(String(format: "Logged %.1f°C", latest.temperatureCelsius))
                } icon: {
                    Image(systemName: "thermometer.medium")
                        .foregroundStyle(.orange)
                }
            }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(DougTheme.cardBackground, in: .rect(cornerRadius: 14))
    }

    // MARK: - Derived

    private var stepTypeIDEnum: StepTypeID {
        StepTypeID(rawValue: step.stepTypeID) ?? .mix
    }

    private var showsMarkDoneButton: Bool {
        guard step.stepStatus == .active else { return false }
        guard step.stepType.classification == .handsOn else { return false }
        if step.stepType.requiresTempReading { return false } // Temp entry handles the completion.
        return true
    }
}
