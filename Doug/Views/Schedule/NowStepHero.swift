import SwiftData
import SwiftUI

/// Prominent hero card for the currently-active (or most-imminent upcoming) step.
struct NowStepHero: View {
    let step: ScheduleStep
    let viewModel: ScheduleViewModel
    let referenceDate: Date
    let onOpenDetail: (ScheduleStep) -> Void
    var onOpenCoach: ((String) -> Void)?

    @Environment(\.modelContext) private var modelContext
    @State private var showTemperatureEntry = false
    @State private var showAbandonConfirm = false
    @State private var showAlreadyStarted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if let info = stalenessInfo {
                stalenessWarning(info)
            } else {
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
            }

            primaryActions
            secondaryActions
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DougTheme.cardBackground, in: .rect(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(accentTint.opacity(0.35), lineWidth: 1.5)
        )
        .sheet(isPresented: $showTemperatureEntry) {
            if let schedule = step.schedule {
                TemperatureEntryView(schedule: schedule, foldStep: step)
            }
        }
        .sheet(isPresented: $showAlreadyStarted) {
            AlreadyStartedSheet(step: step, viewModel: viewModel)
        }
        .confirmationDialog(
            "Abandon this bake?",
            isPresented: $showAbandonConfirm,
            titleVisibility: .visible
        ) {
            Button("Abandon Bake", role: .destructive) {
                viewModel.cancelBake(modelContext: modelContext)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let info = stalenessInfo {
                Text(info.salvageAdvice)
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
            Button {
                onOpenDetail(step)
            } label: {
                Image(systemName: "info.circle")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .padding(6)
                    .contentShape(.rect)
            }
        }
    }

    // MARK: - Staleness

    private func stalenessWarning(_ info: StalenessInfo) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(info.warning)
                    .font(.subheadline)
            }

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "lightbulb.fill")
                    .foregroundStyle(.yellow)
                Text(info.salvageAdvice)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if onOpenCoach != nil {
                let delay = Int(referenceDate.timeIntervalSince(step.computedStartTime) / 60)
                let temp = step.schedule?.kitchenTemperatureCelsius ?? 22
                Button {
                    onOpenCoach?(
                        "I'm \(delay) minutes late for \(step.stepType.label). Kitchen is \(Int(temp))°C. What should I do?"
                    )
                } label: {
                    Label("What should I do?", systemImage: "bubble.left.and.text.bubble.right")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .adaptiveGlassButtonStyle()
            }
        }
        .padding(12)
        .background(.orange.opacity(0.1), in: .rect(cornerRadius: 12))
    }

    // MARK: - Primary actions

    private var primaryActions: some View {
        HStack(spacing: 10) {
            if showsStart, stalenessInfo != nil {
                Button {
                    viewModel.startStepNow(step, modelContext: modelContext)
                } label: {
                    Label("Start Anyway", systemImage: "play.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .adaptiveGlassButtonStyle()
                Button {
                    showAbandonConfirm = true
                } label: {
                    Label("Abandon", systemImage: "xmark.circle")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .adaptiveGlassButtonStyle()
            } else if showsStart {
                Button {
                    viewModel.startStepNow(step, modelContext: modelContext)
                } label: {
                    Label("Start", systemImage: "play.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .adaptiveGlassButtonStyle(prominent: true)
                Button {
                    showAlreadyStarted = true
                } label: {
                    Label("Already Started", systemImage: "clock.arrow.circlepath")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .adaptiveGlassButtonStyle()
            } else if step.stepType.requiresTempReading, step.stepStatus == .active {
                Button {
                    showTemperatureEntry = true
                } label: {
                    Label("Enter Temp", systemImage: "thermometer.medium")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .adaptiveGlassButtonStyle(prominent: true)
            } else if step.stepStatus == .active {
                Button {
                    completeCurrent()
                } label: {
                    Label("Done", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .adaptiveGlassButtonStyle(prominent: true)
            }
        }
    }

    // MARK: - Secondary actions

    @ViewBuilder
    private var secondaryActions: some View {
        if isPaused {
            Button {
                viewModel.resumeSchedule(modelContext: modelContext)
            } label: {
                Label("Resume", systemImage: "play.fill")
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .adaptiveGlassButtonStyle()
        } else if step.stepStatus == .upcoming, !showsStart {
            VStack(spacing: 8) {
                Text("Running late?")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 10) {
                    ForEach([15.0, 30.0, 60.0], id: \.self) { minutes in
                        Button {
                            viewModel.delayStep(step, byMinutes: minutes, modelContext: modelContext)
                        } label: {
                            Text(minutes < 60 ? "+\(Int(minutes))m" : "+1h")
                                .font(.caption.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                        }
                        .adaptiveGlassButtonStyle()
                    }
                }
            }
        } else if step.stepStatus == .active {
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
                    viewModel.extendStep(step, byMinutes: 30, modelContext: modelContext)
                } label: {
                    Label("+30m", systemImage: "plus.circle")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .adaptiveGlassButtonStyle()

                Button {
                    viewModel.pauseSchedule(modelContext: modelContext)
                } label: {
                    Label("Pause", systemImage: "pause.fill")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .adaptiveGlassButtonStyle()
            }
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

    private var stalenessInfo: StalenessInfo? {
        guard showsStart,
              let staleness = step.stepType.staleness
        else { return nil }
        let delay = referenceDate.timeIntervalSince(step.computedStartTime) / 60
        guard delay >= staleness.thresholdMinutes else { return nil }
        return staleness
    }

    private var showsStart: Bool {
        step.stepStatus == .upcoming
            && referenceDate >= step.computedStartTime
    }

    private var isPaused: Bool {
        step.schedule?.pausedAt != nil
    }

    private func completeCurrent() {
        if step.stepType.classification == .handsOn {
            viewModel.markStepDone(step, modelContext: modelContext)
        } else {
            viewModel.finishStepEarly(step, modelContext: modelContext)
        }
    }
}

// MARK: - Already Started Sheet

private struct AlreadyStartedSheet: View {
    let step: ScheduleStep
    let viewModel: ScheduleViewModel

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var startTime: Date

    init(step: ScheduleStep, viewModel: ScheduleViewModel) {
        self.step = step
        self.viewModel = viewModel
        let earliest = Calendar.current.startOfDay(for: Date())
        let initial = max(earliest, step.computedStartTime)
        _startTime = State(initialValue: initial)
    }

    private var earliestAllowed: Date {
        Calendar.current.startOfDay(for: Date())
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker(
                        "Started at",
                        selection: $startTime,
                        in: earliestAllowed ... Date(),
                        displayedComponents: [.hourAndMinute]
                    )
                } footer: {
                    Text("Pick when you actually started this step. The rest of the schedule will shift to match.")
                }
            }
            .navigationTitle("Already Started")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        viewModel.startStepAt(step, at: startTime, modelContext: modelContext)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
