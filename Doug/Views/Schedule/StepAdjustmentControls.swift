import SwiftData
import SwiftUI

/// The five step-adjustment controls: Pause Making / Finish Early / Set Start Time to Now /
/// Add More Time / Shorten this Step. Embedded inside `StepDetailSheet`.
struct StepAdjustmentControls: View {
    let step: ScheduleStep
    let viewModel: ScheduleViewModel
    let onAction: () -> Void // Called after any mutating action so the parent can dismiss / refresh.

    @Environment(\.modelContext) private var modelContext
    @State private var pendingMinutes: Double = 30
    @State private var showMinutePicker: MinutePickerMode?
    @State private var showBakeGuardAlert: PendingGuardAction?

    var body: some View {
        VStack(spacing: 10) {
            row(
                title: isPaused ? "Resume Making" : "Pause Making",
                subtitle: isPaused ? "Un-pause the bake and shift downstream" : "Hold everything while life interrupts",
                systemImage: isPaused ? "play.fill" : "pause.fill",
                tint: .indigo
            ) { tapPauseResume() }

            if canFinishEarly {
                row(
                    title: "Finish Early",
                    subtitle: "This step is already done",
                    systemImage: "checkmark.circle",
                    tint: .green
                ) { viewModel.finishStepEarly(step, modelContext: modelContext); onAction() }
            }

            if canStartNow {
                row(
                    title: "Set Start Time to Now",
                    subtitle: "I'm starting this step late",
                    systemImage: "clock.arrow.circlepath",
                    tint: .blue
                ) { viewModel.startStepNow(step, modelContext: modelContext); onAction() }
            }

            row(
                title: "Add More Time",
                subtitle: "Needs longer than scheduled",
                systemImage: "plus.circle",
                tint: .orange
            ) {
                pendingMinutes = 30
                showMinutePicker = .extend
            }

            if canShorten {
                row(
                    title: "Shorten this Step",
                    subtitle: "Wrap up sooner than planned",
                    systemImage: "minus.circle",
                    tint: .pink
                ) {
                    if isBakeStep {
                        showBakeGuardAlert = .shorten
                    } else {
                        pendingMinutes = 15
                        showMinutePicker = .shorten
                    }
                }
            }
        }
        .sheet(item: $showMinutePicker) { mode in
            MinutePickerSheet(
                mode: mode,
                initialMinutes: pendingMinutes,
                onApply: { minutes in
                    switch mode {
                    case .extend:
                        viewModel.extendStep(step, byMinutes: minutes, modelContext: modelContext)
                    case .shorten:
                        viewModel.shortenStep(step, byMinutes: minutes, modelContext: modelContext)
                    }
                    showMinutePicker = nil
                    onAction()
                },
                onCancel: { showMinutePicker = nil }
            )
        }
        .alert(
            "Bake step warning",
            isPresented: Binding(
                get: { showBakeGuardAlert != nil },
                set: { if !$0 { showBakeGuardAlert = nil } }
            ),
            presenting: showBakeGuardAlert
        ) { action in
            Button("Cancel", role: .cancel) { showBakeGuardAlert = nil }
            Button("Continue", role: .destructive) {
                switch action {
                case .shorten:
                    pendingMinutes = 5
                    showMinutePicker = .shorten
                case .pause:
                    viewModel.pauseSchedule(modelContext: modelContext)
                    onAction()
                }
                showBakeGuardAlert = nil
            }
        } message: { _ in
            Text(
                "Shortening or pausing a bake step risks an under-baked or over-proofed loaf. Only continue if you're confident."
            )
        }
    }

    // MARK: - Derived state

    private var isPaused: Bool {
        step.schedule?.pausedAt != nil
    }

    private var isBakeStep: Bool {
        let id = StepTypeID(rawValue: step.stepTypeID)
        return id == .bakeCovered || id == .bakeUncovered
    }

    private var canFinishEarly: Bool {
        step.stepStatus == .active && Date() < step.computedEndTime
    }

    private var canStartNow: Bool {
        (step.stepStatus == .upcoming || step.stepStatus == .active)
            && Date() > step.computedStartTime
    }

    private var canShorten: Bool {
        step.computedDurationMinutes > 2
    }

    // MARK: - Helpers

    private func tapPauseResume() {
        if isPaused {
            viewModel.resumeSchedule(modelContext: modelContext)
            onAction()
            return
        }
        if isBakeStep {
            showBakeGuardAlert = .pause
        } else {
            viewModel.pauseSchedule(modelContext: modelContext)
            onAction()
        }
    }

    private func row(
        title: String,
        subtitle: String,
        systemImage: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundStyle(tint)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline.weight(.semibold))
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Minute Picker

private enum MinutePickerMode: String, Identifiable {
    case extend, shorten
    var id: String {
        rawValue
    }

    var title: String {
        self == .extend ? "Add More Time" : "Shorten this Step"
    }

    var description: String {
        self == .extend ? "Extend this step by:" : "Shorten this step by:"
    }
}

private enum PendingGuardAction: String, Identifiable {
    case shorten, pause
    var id: String {
        rawValue
    }
}

private struct MinutePickerSheet: View {
    let mode: MinutePickerMode
    let initialMinutes: Double
    let onApply: (Double) -> Void
    let onCancel: () -> Void

    @State private var minutes: Double

    init(
        mode: MinutePickerMode,
        initialMinutes: Double,
        onApply: @escaping (Double) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.mode = mode
        self.initialMinutes = initialMinutes
        self.onApply = onApply
        self.onCancel = onCancel
        _minutes = State(initialValue: initialMinutes)
    }

    private let presets: [Double] = [15, 30, 60]

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text(mode.description)
                    .font(.title3)
                    .padding(.top, 8)

                HStack(spacing: 10) {
                    ForEach(presets, id: \.self) { value in
                        presetChip(value: value)
                    }
                }

                VStack(spacing: 8) {
                    Text(formatted(minutes))
                        .font(.largeTitle.bold().monospacedDigit())
                    Slider(value: $minutes, in: 5 ... 180, step: 5)
                        .accessibilityLabel("Minutes")
                        .accessibilityValue(formatted(minutes))
                    HStack {
                        Text("5m").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text("3h").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal)

                Spacer()

                Button {
                    onApply(minutes)
                } label: {
                    Text("Apply")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .adaptiveGlassButtonStyle(prominent: true)
            }
            .padding()
            .navigationTitle(mode.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func presetChip(value: Double) -> some View {
        Button {
            minutes = value
        } label: {
            Text(formatted(value))
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    minutes == value
                        ? Color.accentColor.opacity(0.2)
                        : Color(.tertiarySystemBackground),
                    in: .capsule
                )
                .overlay(
                    Capsule().strokeBorder(
                        minutes == value ? Color.accentColor : .clear,
                        lineWidth: 1.5
                    )
                )
        }
        .buttonStyle(.plain)
    }

    private func formatted(_ value: Double) -> String {
        let m = Int(value)
        if m >= 60 {
            let h = m / 60
            let rem = m % 60
            return rem > 0 ? "\(h)h \(rem)m" : "\(h)h"
        }
        return "\(m)m"
    }
}
